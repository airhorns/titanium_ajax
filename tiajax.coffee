###
 Titanium $.ajax port from jQuery JavaScript Library v1.4.2
 Original code at http://jquery.com/, Copyright 2010, John Resig
 Dual licensed under the MIT or GPL Version 2 licenses.
 http://jquery.org/license
###

jsre = /=\?(&|$)/
rquery = /\?/
rts = /(\?|&)_=.*?(&|$)/
rurl = /^(\w+:)?\/\/([^\/?#]+)/
r20 = /%20/g

# utils = _
unless utils?
	# Port of Underscore.js extend function, jashkenas is the man.
	utils =
		extend: (obj) ->
			for source in Array.prototype.slice.call(arguments, 1)
    		(obj[key] = val) for key, val of source
  		obj

ajaxHandlerBindings = {}
for name in "ajaxStart ajaxStop ajaxComplete ajaxError ajaxSuccess ajaxSend".split(" ")
	ajaxHandlerBindings[name] = (f) ->
		Titanium.Network.addEventListener name, (e) ->
			# We must pass the function arguments as properties on the event object since
			# Titanium doesn't support multiple event handler arguments, just the one.
			f.call(e, e.xhr, e.s, e.e)
	
utils.extend(Titanium.Network, ajaxHandlerBindings, {
	ajaxSetup: ( settings ) ->
		utils.extend( Titanium.Network.ajaxSettings, settings )

	ajaxSettings:
		global: true
		type: "GET"
		contentType: "application/x-www-form-urlencoded"
		processData: true
		async: true
		timeout: 300000
		traditional: false
		
		# Create the request object; In Titanium it's always going to be the Ti.createHTTPClient
		# This function can be overriden by calling jQuery.ajaxSetup
		xhr: ->
			return Ti.Network.createHTTPClient()
		
		accepts:
			xml: "application/xml, text/xml"
			html: "text/html"
			script: "text/javascript, application/javascript"
			json: "application/json, text/javascript"
			text: "text/plain"
			_default: "*/*"
	
	param: (a) ->
		s = []
		traditional = false

		buildParams = (prefix, obj) ->
			if _.isArray(obj)
				# Serialize array item.
				_.each obj, (i, v) ->
					if ( traditional || /\[\]$/.test( prefix ))
						# Treat each array item as a scalar.
						add( prefix, v )
					else
						# If array item is non-scalar (array or object), encode its
						# numeric index to resolve deserialization ambiguity issues.
						# Note that rack (as of 1.0.0) can't currently deserialize
						# nested arrays properly, and attempting to do so may cause
						# a server error. Possible fixes are to modify rack's
						# deserialization algorithm or to provide an option or flag
						# to force array serialization to be shallow.
						x = if (_.isObject(v) || _.isArray(v)) then i else ""
						p = prefix + "[" + x + "]"
						buildParams( p , v )

			else if ( !traditional && ! _.isNull(obj) && typeof obj == "object" )
				# Serialize object item.
				_.each( obj, (k, v) ->
					buildParams(prefix + "[" + k + "]", v)
				)
			else
				# Serialize scalar item.
				add(prefix, obj)

		add = (key, value) ->
			# If value is a function, invoke it and return its value
			value = if _.isFunction(value)
				value()
			else
				value
			s[ s.length ] = encodeURIComponent(key) + "=" + encodeURIComponent(value)

		# If an array was passed in, assume that it is an array of form elements.
		if _.isArray(a)
			# Serialize the form elements
			_.each(a, ->
				add(this.name, this.value)
			)
		else
			# If traditional, encode the "old" way (the way 1.3.2 or older
			# did it), otherwise encode params recursively.
			for prefix, obj of a
				buildParams(prefix, obj)

		# Return the resulting serialization
		return s.join("&").replace(r20, "+")

	# Last-Modified header cache for next request
	lastModified: {}
	etag: {}

	# Determines if an XMLHttpRequest was successful or not
	httpSuccess: ( xhr ) ->
		try
			return ( xhr.status >= 200 && xhr.status < 300 ) || xhr.status == 304
		catch e

		return false

	# Determines if an XMLHttpRequest returns NotModified
	httpNotModified: ( xhr, url ) ->
		lastModified = xhr.getResponseHeader("Last-Modified")
		etag = xhr.getResponseHeader("Etag")

		if lastModified
			Titanium.Network.lastModified[url] = lastModified

		if etag
			Titanium.Network.etag[url] = etag

		# Opera returns 0 when status is 304
		return xhr.status == 304 || xhr.status == 0

	httpData: ( xhr, type, s ) ->
		ct = xhr.getResponseHeader("content-type") || ""
		xml = type == "xml" || !type && ct.indexOf("xml") >= 0
		data = if xml then xhr.responseXML else xhr.responseText

		if xml && data.documentElement.nodeName == "parsererror"
			Titanium.Network.error( "parsererror" )

		# Allow a pre-filtering function to sanitize the response
		# s is checked to keep backwards compatibility
		if s? && s.dataFilter
			data = s.dataFilter( data, type )

		# The filter can actually parse the response
		if typeof data == "string"
			# Get the JavaScript object, if JSON is used.
			if type == "json" || !type && ct.indexOf("json") >= 0
				data = JSON.parse( data )

		return data

	error: ( msg ) ->
		throw msg

	handleError: ( s, xhr, status, e ) ->
		# If a local callback was specified, fire it
		if s.error
			s.error.call( s.context || s, xhr, status, e )

		# Fire the global callback
		if s.global
			Titanium.Network.fireEvent "ajaxError", {xhr:xhr, s:s, e:e}

	ajax: ( origSettings ) ->
		s = utils.extend({}, Titanium.Network.ajaxSettings, origSettings)
		status = ""
		data = {}
		callbackContext = origSettings && origSettings.context || s
		type = s.type.toUpperCase()

		# convert data if not already a string
		if s.data && s.processData && typeof s.data != "string"
			s.data = Titanium.Network.param( s.data, s.traditional )

		if s.cache == false && type == "GET"
			ts = (new Date).getTime()

			# try replacing _= if it is there
			ret = s.url.replace(rts, "$1_=" + ts + "$2")

			# if nothing was replaced, add timestamp to the end
			s.url = ret + (if (ret == s.url) then ( if rquery.test(s.url) then "&" else "?") + "_=" + ts else "")

		# If data is available, append data to url for get requests
		if s.data && type == "GET"
			s.url += (rquery.test(s.url) ? "&" : "?") + s.data

		# Matches an absolute URL, and saves the domain
		parts = rurl.exec( s.url )
		remote = true
		requestDone = false

		# Create the request object
		xhr = s.xhr()

		if !xhr
			return

		Ti.API.debug("Sending "+type+" request to "+s.url)
		if type == "POST"
			Ti.API.debug("POSTing data:")
			Ti.API.debug(s.data)
		# Open the socket
		# Passing null username, generates a login popup on Opera (#2865)
		if s.username?
			xhr.open(type, s.url, s.async, s.username, s.password)
		else
			xhr.open(type, s.url, s.async)

		# Set the correct header, if data is being sent
		if s.data || origSettings && origSettings.contentType
			xhr.setRequestHeader("Content-Type", s.contentType)

		# Set the If-Modified-Since and/or If-None-Match header, if in ifModified mode.
		if s.ifModified
			if Titanium.Network.lastModified[s.url]
				xhr.setRequestHeader("If-Modified-Since", Titanium.Network.lastModified[s.url])

			if Titanium.Network.etag[s.url]
				xhr.setRequestHeader("If-None-Match", Titanium.Network.etag[s.url])

		# Set header so the called script knows that it's an XMLHttpRequest
		# Only send the header if it's not a remote XHR
		#if !remote
		xhr.setRequestHeader("X-Requested-With", "XMLHttpRequest")

		# Set the Accepts header for the server, depending on the dataType
		xhr.setRequestHeader("Accept",
			if s.dataType && s.accepts[ s.dataType ]
				s.accepts[ s.dataType ] + ", */*"
			else
				s.accepts._default
		)

		# Allow custom headers/mimetypes and early abort
		if s.beforeSend && s.beforeSend.call(callbackContext, xhr, s) == false
			# close opended socket
			xhr.abort()
			return false

		# Wait for a response to come back
		onreadystatechange = xhr.onreadystatechange = ( isTimeout ) ->
			# The request was aborted
			if !xhr || xhr.readyState == 0 || isTimeout == "abort"
				if !requestDone
					complete()

				requestDone = true
				if xhr
					xhr.onreadystatechange = ->

			# The transfer is complete and the data is available, or the request timed out
			else if !requestDone && xhr && (xhr.readyState == 4 || isTimeout == "timeout")
				requestDone = true
				xhr.onreadystatechange = ->

				status = if isTimeout == "timeout"
					"timeout"
				else
					if !Titanium.Network.httpSuccess( xhr )
						"error"
					else
						if s.ifModified && Titanium.Network.httpNotModified( xhr, s.url )
							"notmodified"
						else
							"success"

				errMsg = ""

				if status == "success"
					# Watch for, and catch, XML document parse errors
					try
						# process the data (runs the xml through httpData regardless of callback)
						data = Titanium.Network.httpData( xhr, s.dataType, s )
					catch err
						status = "parsererror"
						errMsg = err

				# Make sure that the request was successful or notmodified
				if status == "success" || status == "notmodified"
						success()
				else
					Titanium.Network.handleError(s, xhr, status, errMsg)

				# Fire the complete handlers
				complete()

				if isTimeout == "timeout"
					xhr.abort()

				# Stop memory leaks
				if s.async
					xhr = null

		# Override the abort handler, if we can
		try
			oldAbort = xhr.abort
			xhr.abort = ->
				if xhr
					oldAbort.call( xhr )
				onreadystatechange( "abort" )
		catch e

		# Timeout checker
		if s.async && s.timeout > 0
			setTimeout( ->
				# Check to see if the request is still happening
				if xhr && !requestDone
					onreadystatechange( "timeout" )
			, s.timeout)

		# Send the data
		try
			xhr.send( if type == "POST" || type == "PUT" || type == "DELETE" then s.data else null )
		catch e
			Titanium.Network.handleError(s, xhr, null, e)
			# Fire the complete handlers
			complete()
		
		trigger = (type, arg) ->
			obj = if s.context then s.context else Titanium.Network
			if obj?.fireEvent?
				obj.fireEvent type, arg

		success =  ->
			# If a local callback was specified, fire it and pass it the data
			if s.success
				s.success.call( callbackContext, data, status, xhr )

			# Fire the global callback
			if s.global
				trigger( "ajaxSuccess", {xhr:xhr, s:s} )

		complete = ->
			# Process result
			if s.complete
				s.complete.call( callbackContext, xhr, status)

			# The request was completed
			if s.global
				trigger( "ajaxComplete", {xhr:xhr, s:s} )
			

			# Handle the global AJAX counter
			if s.global && ! --jQuery.active
				Titanium.Network.fireEvent( "ajaxStop" )

		# return XMLHttpRequest to allow aborting the request etc.
		return xhr
})

Titanium.ajax = Titanium.Network.ajax
