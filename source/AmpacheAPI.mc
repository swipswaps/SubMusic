using Toybox.Time;
using Toybox.Cryptography;
using Toybox.StringUtil;
using Toybox.Communications;
using Toybox.Lang;
 
class AmpacheAPI extends Api {
 
	private var d_session;	// handshake response
	private var d_expire;	// Moment of session expire
	
	function initialize(settings, progress, fallback) {
		Api.initialize("/server/json.server.php");
		Api.update(settings);		// update settings without destroying session

		// set callbacks
		Api.setProgressCallback(progress);
		Api.setFallback(fallback);

    	System.println("AmpacheAPI::initialize(client name: " + client() + " )");
		
		// check if auth is expired, it may be usable!
		d_expire = new Time.Moment(0);
		d_session = Application.Storage.getValue("AMPACHE_API_SESSION");
		if ((d_session == null)
			|| (d_session["session_expire"] == null)) {
			return;
		}
		var expire = parseISODate(d_session["session_expire"]);
		if (expire == null) {
			return;
		}
		d_expire = expire;
	}
	
	/*
	 * API call 'handshake'
	 */
	function handshake(callback) {
		Api.setCallback(callback);

		var hasher = new Cryptography.Hash({:algorithm => Cryptography.HASH_SHA256});
		
		// get the time
		var timestamp = Time.now().value().format("%i");
		
		// construct the auth
		hasher.update(string_to_ba(timestamp));
		var hash = key();
		hasher.update(string_to_ba(hash));
		var auth = ba_to_hexstring(hasher.digest());
		
		var params = {
			"action" => "handshake",
			"user" => usr(),
			"timestamp" => timestamp,
			"auth" => auth,
		};
		
		System.println("AmpacheAPI::handshake with timestamp " + timestamp + " and auth " + auth);
		
		Communications.makeWebRequest(url(), params, {}, self.method(:onHandshake));
	}
	
	function onHandshake(responseCode, data) {
		System.println("AmpacheAPI::onHandshake with responseCode " + responseCode + " payload " + data);
		
		// errors are filtered first
		var error = checkDictionaryResponse(responseCode, data);
		if (error) {
			d_fallback.invoke(error);
			return;
		}
		
		// store the session
		d_session = data;
		Application.Storage.setValue("AMPACHE_API_SESSION", d_session);

		// store the auth key for future communication
		var expire = parseISODate(d_session["session_expire"]);
		if (expire != null) {
			d_expire = expire;
		}
		d_callback.invoke();
	}
	
	function ping(callback) {
		Api.setCallback(callback);
		
		var params = {};
		params.put("action", "ping");
		
		// auth is optional
		// params.put("auth", d_session.get("auth"));
		
		Communications.makeWebRequest(url(), params, {}, self.method(:onDictionaryResponse));
	}
	
	function record_play(callback, params) {
		System.println("AmpacheAPI::record_play( params: " + params + ")");
		
		Api.setCallback(callback);

		params.put("action", "record_play");
		params.put("auth", d_session.get("auth"));
		
		Communications.makeWebRequest(url(), params, {}, self.method(:onDictionaryResponse));
	}
	
	function scrobble(callback, params) {
		System.println("AmpacheAPI::scrobble( params: " + params + ")");
		
		Api.setCallback(callback);

		params.put("action", "scrobble");
		params.put("auth", d_session.get("auth"));
		
		Communications.makeWebRequest(url(), params, {}, self.method(:onDictionaryResponse));
	}
	
	// returns array of playlist objects
	function playlists(callback, params) {
		System.println("AmpacheAPI::playlists( params: " + params + ")");
		
		Api.setCallback(callback);

		params.put("action", "playlists");
		params.put("auth", d_session.get("auth"));
		
		Communications.makeWebRequest(url(), params, {}, self.method(:onArrayResponse));
	}
	
	// returns single playlist info
	function playlist(callback, params) {
		System.println("AmpacheAPI::playlist( id: " + params["filter"] + ")");
		
		Api.setCallback(callback);
		
		params.put("action", "playlist");
		params.put("auth", d_session.get("auth"));
		Communications.makeWebRequest(url(), params, {}, self.method(:onArrayResponse));
	}
	
	// returns array of song objects
	function playlist_songs(callback, params) {
		System.println("AmpacheAPI::playlist_songs( id: " + params["filter"] + ")");
		
		Api.setCallback(callback);
		
		params.put("action", "playlist_songs");
		params.put("auth", d_session.get("auth"));
		Communications.makeWebRequest(url(), params, {}, self.method(:onArrayResponse));
	}
	
	// returns refId to the downloaded song
	function stream(callback, params, encoding) {
		System.println("AmpacheAPI::stream( id : " + params["id"] + " )");

		Api.setCallback(callback);
		
		params.put("action", "stream");
		params.put("auth", d_session.get("auth"));
		
		if (!params.hasKey("type")) {
			params.put("type", "song");
		}
		var options = {
			:method => Communications.HTTP_REQUEST_METHOD_GET,
			:responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_AUDIO,
			:mediaEncoding => encoding,
			:fileDownloadProgressCallback => method(:onProgress),
		};
		Communications.makeWebRequest(url(), params, options, self.method(:onStream));
	}
	
	function onStream(responseCode, data) {
		System.println("AmpacheAPI::onStream with responseCode: " + responseCode);
		
		// check if request was successful and response is ok
		var error = checkResponse(responseCode, data);
		if (error) {
			d_fallback.invoke(error);
			return;
		}
		d_callback.invoke(data.getId());
    }
    
	// returns true if the current session is not expired (optionally pass in duration for session)
	function session(duration) {
		System.println("AmpacheAPI::session(duration: " + duration + ");" + " Time now: " + Time.now().value() + ", session expires: " + d_expire.value());
		
		var now = new Time.Moment(Time.now().value());
		if (duration != null) {
			now.add(duration);
		}
		return now.lessThan(d_expire);
	}

	/*
	 * onArrayResponse
	 * 
	 * default handler for actions that return an array
	 */
	function onArrayResponse(responseCode, data) {
		System.println("AmpacheAPI::onArrayResponse with responseCode: " + responseCode + ", payload " + data);
		
		// errors are filtered first
		var error = checkArrayResponse(responseCode, data);
		if (error) {
			d_fallback.invoke(error);
			return;
		}
		d_callback.invoke(data);
	}
	
	function checkArrayResponse(responseCode, data) {
		var error = checkResponse(responseCode, data);
		if (error) { return error; }
		
		// finally, expecting array
		if (!(data instanceof Lang.Array)) { return new AmpacheError(null); }
		return null;
	}
	
	/*
	 * onDictionaryResponse
	 *
	 * Default handler for actions that return a dictionary
	 */
	function onDictionaryResponse(responseCode, data) {
		System.println("AmpacheAPI::onDictionaryResponse with responseCode " + responseCode + " payload " + data);
		
		// errors are filtered first
		var error = checkDictionaryResponse(responseCode, data);
		if (error) {
			d_fallback.invoke(error);
			return;
		}
		
		d_callback.invoke(data);
	}
	
	function checkDictionaryResponse(responseCode, data) {
		var error = checkResponse(responseCode, data);
		if (error) { return error; }
		
		// finally, expecting Dictionary
		if (!(data instanceof Lang.Dictionary)) { return new AmpacheError(null); }
		return null;
	}
	
	/*
	 * checkResponse
	 *
	 * returns response / api errors if found
	 */
	function checkResponse(responseCode, data) {
		var error = Api.checkResponse(responseCode, data);
		if (error) { return error; }
		return AmpacheError.is(responseCode, data);
	}
	
	// converts rfc3339 formatted timestamp to Time::Moment (null on error)
	function parseISODate(date) {
		// assert(date instanceOf String)
		if (date == null) {
			return null;
		}
		
		// 0123456789012345678901234
		// 2011-10-17T13:00:00-07:00
		// 2011-10-17T16:30:55.000Z
		// 2011-10-17T16:30:55Z
		if (date.length() < 20) {
			return null;
		}
		
		var moment = Time.Gregorian.moment({
			:year	=> date.substring( 0,  4).toNumber(),
			:month	=> date.substring( 5,  7).toNumber(),
			:day	=> date.substring( 8, 10).toNumber(),
			:hour	=> date.substring(11, 13).toNumber(),
			:minute => date.substring(14, 16).toNumber(),
			:second => date.substring(17, 19).toNumber(),
		});
		var suffix = date.substring(19, date.length());
		
		// skip over to time zone
		var tz = 0;
		if (suffix.substring(tz, tz + 1).equals(".")) {
			while (tz < suffix.length()) {
				var first = suffix.substring(tz, tz + 1);
				if ("-+Z".find(first) != null) {
					break;
				}
				tz++;
			}
		}
		
		if (tz >= suffix.length()) {
			// no timezone given
			return null;
		}
		var tzOffset = 0;
		if (!suffix.substring(tz, tz + 1).equals("Z")) {
			// +HH:MM
			if (suffix.length() - tz < 6) {
				return null;
			}
			tzOffset = suffix.substring(tz + 1, tz + 3).toNumber() * Time.Gregorian.SECONDS_PER_HOUR;
			tzOffset += suffix.substring(tz + 4, tz + 6).toNumber() * Time.Gregorian.SECONDS_PER_MINUTE;
		
			var sign = suffix.substring(tz, tz + 1);
			if (sign.equals("+")) {
				tzOffset = -tzOffset;
			} else if (sign.equals("-") && tzOffset == 0) {
				// -00:00 denotes unknown timezone
				return null;
			}
		}
		return moment.add(new Time.Duration(tzOffset));
	}
	
	function string_to_ba(string) {
		var options = {
			:fromRepresentation => StringUtil.REPRESENTATION_STRING_PLAIN_TEXT,
			:toRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY,
		};
		return StringUtil.convertEncodedString(string, options);
	}
	
	function ba_to_hexstring(ba) {
		var options = {
			:fromRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY,
			:toRepresentation => StringUtil.REPRESENTATION_STRING_HEX,
		};
		return StringUtil.convertEncodedString(ba, options);
	}
	
	// function update(settings) {
	// 	System.println("AmpacheAPI::update(settings)");
		
	// 	// update the settings
	// 	set(settings);
		
	// 	deleteSession();
	// }
	
	// function set(settings) {
	// 	d_url = settings.get("api_url") + "/server/json.server.php";
	// 	d_usr = settings.get("api_usr");
		
	// 	// hash the password
	// 	var hasher = new Cryptography.Hash({:algorithm => Cryptography.HASH_SHA256});
	// 	hasher.update(string_to_ba(settings.get("api_key")));
	// 	d_hash = ba_to_hexstring(hasher.digest());
		
	// 	System.println("AmpacheAPI::set(url: " + d_url + ", user: " + d_usr + ", pass: " + d_hash + ")");
	// }

	// @override
	function update(settings) {
		Api.update(settings);

		deleteSession();
	}

	// @override
	function updateKey(key) {
		// hash the password
		var hasher = new Cryptography.Hash({:algorithm => Cryptography.HASH_SHA256});
		hasher.update(string_to_ba(key));
		var hash = ba_to_hexstring(hasher.digest());
		Api.updateKey(hash);
	}

	function deleteSession() {
		// reset the session
		d_expire = new Time.Moment(0);
		Application.Storage.deleteValue("AMPACHE_API_SESSION");
		d_session = null;
	}
}