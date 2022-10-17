// GameAnalytics - https://restapidocs.gameanalytics.com/
// Google Analytics - https://developers.google.com/analytics/devguides/collection/protocol/v1/
// Log4j - https://logging.apache.org/log4j/2.x/manual/layouts.html
// sentry.io - https://develop.sentry.dev/sdk/overview/    https://develop.sentry.dev/sdk/event-payloads/https://develop.sentry.dev/sdk/event-payloads/

//Redirect exception_unhandled_handler() to our own internal function
//The bound exception handler will still be executed
#macro exception_unhandled_handler      __SnitchCrashSetGMHandler
#macro __exception_unhandled_handler__  exception_unhandled_handler



#macro SNITCH_VERSION               "3.0.0"
#macro SNITCH_DATE                  "2021-12-30"
#macro SNITCH_SHARED_EVENT_PAYLOAD  global.__snitchSharedEventPayload
#macro SNITCH_OS_NAME               global.__snitchOSName
#macro SNITCH_OS_VERSION            global.__snitchOSVersion
#macro SNITCH_ENVIRONMENT_NAME      global.__snitchEnvironmentName
#macro SNITCH_BROWSER               global.__snitchBrowser
#macro SNITCH_OS_INFO               global.__snitchOSInfo
#macro SNITCH_BOOT_PARAMETERS       global.__snitchBootParameters
#macro SNITCH_RUNNING_FROM_IDE      global.__snitchRunningFromIDE
#macro SNITCH_FRAMES                global.__snitchFrames
#macro SNITCH_FOCUS_FRAMES          global.__snitchFocusFrames
#macro SNITCH_SESSION_TIME          (current_time - global.__snitchSessionStartTime)
#macro SNITCH_FOCUS_TIME            global.__snitchFocusTime

#macro __SNITCH_DEBUG  (global.__snitchRunningFromIDE && true)



//Initialize the library
__SnitchInit();

function __SnitchInit()
{
    //Don't initialize twices
    static _initialized = false;
    if (_initialized) return;
    _initialized = true;
    
    if ((SNITCH_INTEGRATION_MODE != 0) && !SNITCH_INTEGRATION_WARNING_READ)
    {
        __SnitchError("Bug tracking integrations open up potential security risks.\n1. Never share access keys with anyone\n2. Use .gitignore to ignore __SnitchConfigIntegrationKeys.gml if hosting your work publicly\n3. Do your absolute best to protect the privacy of your players\n \nPlease set SNITCH_INTEGRATION_WARNING_READ to <true> to acknowledge this warning");
        game_end();
        return;
    }
    
    
    
    global.__snitchGMExceptionHandler = undefined;
    global.__snitchFrames             = 0;
    global.__snitchSessionStartTime   = current_time;
    global.__snitchFocusFrames        = 0;
    global.__snitchFocusTime          = 0;
    
    global.__snitchCrashCapture       = false;
    global.__snitchLogToFileEnabled   = false;
    global.__snitchIntegrationEnabled = false;
    
    //Determine how the application is being run and whether we should capture crashes
    global.__snitchRunningFromIDE = (GM_build_type == "run");
    global.__snitchCrashCapture   = global.__snitchRunningFromIDE? SNITCH_CRASH_CAPTURE_FROM_IDE : SNITCH_CRASH_CAPTURE_COMPILED;
    
    //Log files
    global.__snitchWroteLogFileHeader = false;
    global.__snitchZerothLogFile      = string_replace(SNITCH_LOG_FILENAME, "#", "0");
    global.__snitchLogFileBuffer      = buffer_create(SNITCH_LOG_BUFFER_START_SIZE, buffer_grow, 1);
    
    //Network transmission
    global.__snitchNetworkConnected          = false;
    global.__snitchNetworkSocket             = undefined;
    global.__snitchNetworkEnabled            = false;
    global.__snitchNetworkOutgoingPort       = SNITCH_NETWORK_DEFAULT_OUTGOING_PORT;
    global.__snitchNetworkTargetPort         = SNITCH_NETWORK_DEFAULT_RECEIVER_PORT;
    global.__snitchNetworkTargetIP           = SNITCH_NETWORK_DEFAULT_RECEIVER_IP;
    global.__snitchNetworkTestTime           = undefined;
    global.__snitchNetworkTested             = false;
    global.__snitchNetworkConnectionAttempts = 0;
    global.__snitchNetworkAbandoned          = false;
    global.__snitchNetworkPendingMessages    = [];
    
    //HTTP-related tracking
    global.__snitchHTTPTestTime             = undefined;
    global.__snitchHTTPHeaderMap            = ds_map_create(); //Has to be a map due to GameMaker's HTTP request API
    global.__snitchHTTPRequests             = {};
    global.__snitchRequestBackups           = {};
    global.__snitchRequestBackupOrder       = [];
    global.__snitchRequestBackupResendTime  = -SNITCH_REQUEST_BACKUP_RESEND_DELAY; //Try to send a request backup immediately on boot
    global.__snitchRequestBackupResendIndex = 0;
    global.__snitchRequestBackupFailures    = 0;
    
    
    
    //Build an array for the boot parameters
    SNITCH_BOOT_PARAMETERS = [];
    var _i = 0;
    repeat(parameter_count())
    {
        array_push(SNITCH_BOOT_PARAMETERS,  parameter_string(_i));
        ++_i;
    }
    
    if (SNITCH_NETWORK_MODE == 2) network_set_config(network_config_connect_timeout, SNITCH_NETWORK_CONNECTION_TIMEOUT);
    
    
    
    #region Set SNITCH_OS_NAME, SNITCH_OS_VERSION, SNITCH_ENVIRONMENT_NAME, SNITCH_BROWSER, SNITCH_OS_INFO
        
    SNITCH_OS_NAME          = "Unknown (=" + string(os_type) + ")";
    SNITCH_OS_VERSION       = "v" + string(os_version);
    SNITCH_BROWSER          = "Unknown browser";
    SNITCH_ENVIRONMENT_NAME = SNITCH_OS_NAME + " " + SNITCH_OS_VERSION;
    
    switch(os_type)
    {
        case os_windows:
        case os_win8native:
            SNITCH_OS_NAME = "Windows";
              
            switch(os_version)
            {
                case 327680: SNITCH_OS_VERSION = "2000";  break;
                case 327681: SNITCH_OS_VERSION = "XP";    break;
                case 237862: SNITCH_OS_VERSION = "XP";    break;
                case 393216: SNITCH_OS_VERSION = "Vista"; break;
                case 393217: SNITCH_OS_VERSION = "7";     break;
                case 393218: SNITCH_OS_VERSION = "8";     break;
                case 393219: SNITCH_OS_VERSION = "8.1";   break;
                case 655360: SNITCH_OS_VERSION = "10";    break;
            }
        break;
        
        case os_uwp:
            SNITCH_OS_NAME     = "UWP";
            SNITCH_OS_VERSION  = string(os_version);
            SNITCH_ENVIRONMENT_NAME = SNITCH_OS_NAME + " " + SNITCH_OS_VERSION;
        break;
        
        case os_linux:
            SNITCH_OS_NAME     = "Linux";
            SNITCH_OS_VERSION  = string(os_version);
            SNITCH_ENVIRONMENT_NAME = SNITCH_OS_NAME + " " + SNITCH_OS_VERSION;
        break;
        
        case os_macosx:
            SNITCH_OS_NAME     = "macOS";
            SNITCH_OS_VERSION  = string(os_version >> 24) + "." + string((os_version >> 12) & 0xfff);
            SNITCH_ENVIRONMENT_NAME = SNITCH_OS_NAME + " " + SNITCH_OS_VERSION;
        break;
        
        case os_ios:
            SNITCH_OS_NAME     = "iOS";
            SNITCH_OS_VERSION  = string(os_version >> 24) + "." + string((os_version >> 12) & 0xfff);
            SNITCH_ENVIRONMENT_NAME = SNITCH_OS_NAME + " " + SNITCH_OS_VERSION;
        break;
        
        case os_android:
            SNITCH_OS_NAME = "Android";
            
            switch (os_version)
            {
                case 21: SNITCH_OS_VERSION = "Lollipop";    break;
                case 22: SNITCH_OS_VERSION = "Lollipop";    break;
                case 23: SNITCH_OS_VERSION = "Marshmallow"; break;
                case 24: SNITCH_OS_VERSION = "Nougat";      break;
                case 25: SNITCH_OS_VERSION = "Oreo";        break;
                case 26: SNITCH_OS_VERSION = "Pie";         break;
                
                default:
                    if (os_version >= 27)
                    {
                        SNITCH_OS_VERSION = "v" + string(os_version - 17);
                    }
                break;
            }
            
            SNITCH_ENVIRONMENT_NAME = SNITCH_OS_NAME + " " + SNITCH_OS_VERSION;
        break;
        
        case os_tvos:         SNITCH_OS_NAME = "tvOS";             break;
        case os_ps3:          SNITCH_OS_NAME = "PlayStation 3";    break;
        case os_ps4:          SNITCH_OS_NAME = "PlayStation 4";    break;
        case os_ps5:          SNITCH_OS_NAME = "PlayStation 5";    break;
        case os_psvita:       SNITCH_OS_NAME = "PlayStation Vita"; break;
        case os_xboxone:      SNITCH_OS_NAME = "Xbox One";         break;
        case os_xboxseriesxs: SNITCH_OS_NAME = "Xbox Series X/S";  break;
        case os_switch:       SNITCH_OS_NAME = "Switch";           break;
        case os_operagx:      SNITCH_OS_NAME = "GX.games";         break;
    }
    
    //Figure out what browser we're using
    switch(os_browser)
    {
        case browser_not_a_browser: SNITCH_BROWSER = "Not a browser";     break;
        case browser_ie:            SNITCH_BROWSER = "Internet Explorer"; break;
        case browser_ie_mobile:     SNITCH_BROWSER = "Internet Explorer"; break;
        case browser_firefox:       SNITCH_BROWSER = "Firefox";           break;
        case browser_chrome:        SNITCH_BROWSER = "Chrome";            break;
        case browser_safari:        SNITCH_BROWSER = "Safari";            break;
        case browser_safari_mobile: SNITCH_BROWSER = "Safari";            break;
        case browser_opera:         SNITCH_BROWSER = "Opera";             break;
    }
    
    //If we're on a browser, use the browser's name instead
    if (os_browser == browser_not_a_browser)
    {
        SNITCH_ENVIRONMENT_NAME = SNITCH_OS_NAME + " " + SNITCH_OS_VERSION;
    }
    else
    {
        SNITCH_ENVIRONMENT_NAME = SNITCH_BROWSER;
    }
    
    //Turn the os_get_info() map into a struct for serialization
    SNITCH_OS_INFO = {};
    if (os_type != os_switch) //TODO - Workaround for a crash on Switch (runtime 2.3.6   2022-02-04)
    {
        var _infoMap = os_get_info();
        var _key = ds_map_find_first(_infoMap);
        repeat(ds_map_size(_infoMap))
        {
            SNITCH_OS_INFO[$ _key] = _infoMap[? _key];
            _key = ds_map_find_next(_infoMap, _key);
        }
        ds_map_destroy(_infoMap);
    }
    
    #endregion
    
    
    
    if (SNITCH_LOG_ON_BOOT) SnitchLogSet(true);
    if (SNITCH_NETWORK_ON_BOOT) SnitchNetworkSet(true);
    __SnitchTrace("Welcome to Snitch by @jujuadams! This is version " + string(SNITCH_VERSION) + ", " + string(SNITCH_DATE));
    __SnitchTrace("Running ", global.__snitchRunningFromIDE? "from IDE" : "compiled executable", ", crash capture turned ", global.__snitchCrashCapture? "on" : "off");
    
    
    
    if (global.__snitchCrashCapture)
    {
        __exception_unhandled_handler__(__SnitchExceptionHandler);
    }
    
    if (SNITCH_REQUEST_BACKUP_COUNT < 1)
    {
        __SnitchError("SNITCH_REQUEST_BACKUP_COUNT must be greater than zero");
    }
    
    if (SNITCH_ALLOW_LOG_BOOT_PARAMETER && (os_type == os_windows))
    {
        var _i = 0;
        repeat(parameter_count())
        {
            if (parameter_string(_i) == "-log")
            {
                SnitchLogSet(true);
                if (SnitchLogGet() && (SNITCH_LOG_BOOT_PARAMETER_CONFIRMATION != "")) show_message(SNITCH_LOG_BOOT_PARAMETER_CONFIRMATION);
                break;
            }
            
            _i++;
        }
    }
    
    
    
    //Create the shared event payload
    SNITCH_SHARED_EVENT_PAYLOAD = __SnitchSentrySharedEventPayload();
    
    if (SNITCH_REQUEST_BACKUP_ENABLE && (SNITCH_INTEGRATION_MODE > 0))
    {
        var _loadedManifest = false;
        try
        {
            var _buffer = buffer_load(SNITCH_REQUEST_BACKUP_MANIFEST_FILENAME);
            _loadedManifest = true;
            
            var _json = buffer_read(_buffer, buffer_string);
            global.__snitchRequestBackupOrder = json_parse(_json);
            
            if (!is_array(global.__snitchRequestBackupOrder)) throw "Not an array";
        }
        catch(_error)
        {
            if (!_loadedManifest)
            {
                __SnitchTrace("Could not find request backup manifest");
            }
            else
            {
                __SnitchTrace("Request backup manifest was corrupted");
            }
            
            global.__snitchRequestBackupOrder = [];
        }
        finally
        {
            if (_loadedManifest) buffer_delete(_buffer);
        }
        
        if (_loadedManifest)
        {
            var _expected = array_length(global.__snitchRequestBackupOrder);
            var _missing = 0;
            
            var _i = _expected - 1;
            repeat(_expected)
            {
                var _uuid = global.__snitchRequestBackupOrder[_i];
                
                var _filename = __SnitchRequestBackupFilename(_uuid);
                if (!file_exists(_filename))
                {
                    _missing++;
                    array_delete(global.__snitchRequestBackupOrder, _i, 1);
                }
                else
                {
                    var _buffer = buffer_load(_filename);
                    
                    if (buffer_get_size(_buffer) <= 0)
                    {
                        //If the buffer is empty, delete the file on disk and report this event as missing
                        _missing++;
                        file_delete(_filename);
                    }
                    else
                    {
                        //Otherwise read out a string from the buffer and create a new request
                        var _request = new __SnitchClassRequest(_uuid, buffer_read(_buffer, buffer_text));
                        _request.savedBackup = true;
                        global.__snitchRequestBackups[$ _uuid] = _request;
                    }
                    
                    buffer_delete(_buffer);
                }
                
                --_i;
            }
            
            __SnitchTrace("Found ", array_length(global.__snitchRequestBackupOrder), " request backups (", _expected, " in manifest, of which ", _missing, " were missing)");
        }
        
        __SnitchRequestBackupSaveManifest();
    }
    
    
    if (SNITCH_INTEGRATION_MODE > 0)
    {
        //Force a network connection if possible
        os_is_network_connected(true);
        
        //Send off a ping to test if SnitchHTTPAsyncEvent() has been placed in the correct event
        http_get("https://www.google.com/");
        global.__snitchHTTPTestTime = SNITCH_FOCUS_TIME;
    }
    
    switch(SNITCH_INTEGRATION_MODE)
    {
        //Google Analytics
        case 1:
            global.__snitchClientID = SnitchGenerateUUID4String(true);
            global.__snitchEndpoint = "https://www.google-analytics.com/mp/collect?measurement_id=" + SNITCH_GOOGLE_ANALYTICS_MEASUREMENT_ID + "&api_secret=" + SNITCH_GOOGLE_ANALYTICS_API_SECRET;
            
            if (__SNITCH_DEBUG)
            {
                __SnitchTrace("Google Analytics measurement ID = \"", SNITCH_GOOGLE_ANALYTICS_MEASUREMENT_ID, "\"");
                __SnitchTrace("Google Analytics API secret = \"", SNITCH_GOOGLE_ANALYTICS_API_SECRET, "\"");
                __SnitchTrace("Google Analytics endpoint = \"", global.__snitchEndpoint, "\"");
            }
        break;
        
        //sentry.io
        case 2:
            var _DSN = SNITCH_SENTRY_DSN_URL;
            
            var _protocolPosition = string_pos("://", _DSN);
            if (_protocolPosition == 0) __SnitchError("No protocol found in DSN string");
            var _protocol = string_copy(_DSN, 1, _protocolPosition-1);
            
            var _atPosition = string_pos("@", _DSN);
            if (_atPosition == 0) __SnitchError("No @ found in DSN string");
            
            global.__snitchSentryPublicKey = string_copy(_DSN, _protocolPosition + 3, _atPosition - (_protocolPosition + 3));
            if (global.__snitchSentryPublicKey == "") __SnitchError("No public key found in DSN string");
            
            var _slashPosition = string_last_pos("/", _DSN);
            
            var _DSNHostPath = string_copy(_DSN, _atPosition + 1, _slashPosition - (_atPosition + 1));
            if (_DSNHostPath == "") __SnitchError("No host/path found in DSN string");
            
            var _DSNProject = string_copy(_DSN, _slashPosition + 1, string_length(_DSN) - _slashPosition);
            if (_DSNProject == "") __SnitchError("No project found in DSN string");
            
            global.__snitchEndpoint = _protocol + "://" + _DSNHostPath + "/api/" + _DSNProject + "/store/";
            
            //Build an auth string for later HTTP requests
            //We fill in the timestamp later when sending the request
            global.__snitchSentryAuthString = "Sentry sentry_version=7, sentry_client=Snitch/" + string(SNITCH_VERSION) + ", sentry_key=" + global.__snitchSentryPublicKey + ", sentry_timestamp=";
            
            if (__SNITCH_DEBUG)
            {
                __SnitchTrace("Sentry public key = \"", global.__snitchSentryPublicKey, "\"");
                __SnitchTrace("Sentry endpoint = \"", global.__snitchEndpoint, "\"");
            }
        break;
        
        //GameAnalytics
        case 3:
            global.__snitchSessionID = SnitchGenerateUUID4String(true);
            
            if ((SNITCH_GAMEANALYTICS_GAME_KEY == "5c6bcb5402204249437fb5a7a80a4959") && (SNITCH_GAMEANALYTICS_SECRET_KEY == "16813a12f718bc5c620f56944e1abc3ea13ccbac"))
            {
                __SnitchTrace("Using GameAnalytics' sandbox endpoint");
                global.__snitchEndpoint = "https://sandbox-api.gameanalytics.com/v2/" + SNITCH_GAMEANALYTICS_GAME_KEY + "/events";
            }
            else
            {
                global.__snitchEndpoint = "https://api.gameanalytics.com/v2/" + SNITCH_GAMEANALYTICS_GAME_KEY + "/events";
            }
            
            if (__SNITCH_DEBUG)
            {
                __SnitchTrace("GameAnalytics session ID = \"", global.__snitchSessionID, "\"");
                __SnitchTrace("GameAnalytics endpoint = \"", global.__snitchEndpoint, "\"");
                __SnitchTrace("GameAnalytics secret key = \"", SNITCH_GAMEANALYTICS_SECRET_KEY, "\"");
            }
        break;
        
        //Bugsnag
        case 4:
            if (__SNITCH_DEBUG)
            {
                __SnitchTrace("Bugsnag API key = \"", SNITCH_BUGSNAG_API_KEY, "\"");
            }
        break;
        
        //DeltaDNA
        case 5:
            global.__snitchSessionID = SnitchGenerateUUID4String(true);
            
            //The endpoint is modified in __SnitchDeltaDNAHTTPRequest()
            global.__snitchEndpoint = SNITCH_DELTADNA_COLLECT_URL + "/" + SNITCH_DELTADNA_ENVIRONMENT_KEY;
            if (SNITCH_DELTADNA_SECRET_KEY != "") global.__snitchEndpoint += "/hash/";
            
            if (__SNITCH_DEBUG)
            {
                __SnitchTrace("DeltaDNA session ID = \"", global.__snitchSessionID, "\"");
                __SnitchTrace("DeltaDNA endpoint = \"", global.__snitchEndpoint, "\"");
                __SnitchTrace("DeltaDNA secret key = \"", SNITCH_DELTADNA_SECRET_KEY, "\"");
            }
        break;
    }
    
    if (SNITCH_INTEGRATION_ON_BOOT) SnitchIntegrationSet(true);
    
    
    
    //Set up a per-frame request handler
    time_source_start(time_source_create(time_source_global, 1, time_source_units_frames, function()
    {
        global.__snitchFrames++;
        if (!os_is_paused() && window_has_focus())
        {
            global.__snitchFocusFrames++;
            global.__snitchFocusTime += delta_time/1000;
        }
        
        //Perform HTTP event test timeout
        //This will throw an error if the user hasn't called SnitchHTTPAsyncEvent()
        if (SNITCH_INTEGRATION_MODE > 0)
        {
            if ((global.__snitchHTTPTestTime != undefined) && (SNITCH_FOCUS_TIME - global.__snitchHTTPTestTime > __SNITCH_HTTP_TEST_TIMEOUT))
            {
                if (SNITCH_RUNNING_FROM_IDE)
                {
                    __SnitchError("HTTP ping failed to resolve\nPlease check that SnitchHTTPAsyncEvent() is being called in an HTTP Async event in a persistent object");
                }
                else
                {
                    SnitchError("HTTP ping failed to resolve. Please check that SnitchHTTPAsyncEvent() is being called in a HTTP Async event in a persistent object").SendAll();
                }
            }
        }
        
        if (SNITCH_NETWORK_MODE == 2)
        {
            if (!global.__snitchNetworkTested && (global.__snitchNetworkTestTime != undefined) && (SNITCH_FOCUS_TIME - global.__snitchNetworkTestTime > SNITCH_NETWORK_CONNECTION_TIMEOUT + 1000))
            {
                if (SNITCH_RUNNING_FROM_IDE)
                {
                    __SnitchError("TCP connection failed to resolve\nPlease check that SnitchNetworkingAsyncEvent() is being called in a Networking Async event in a persistent object");
                }
                else
                {
                    SnitchError("TCP connection failed to resolve. Please check that SnitchNetworkingAsyncEvent() is being called in a Networking Async event in a persistent object").SendAll();
                }
            }
            
            if (global.__snitchNetworkConnected)
            {
                //Churn through the pending messages and clear them out
                repeat(ceil(sqrt(array_length(global.__snitchNetworkPendingMessages))))
                {
                    __SnitchSendStringToNetwork(global.__snitchNetworkPendingMessages[0]);
                    array_delete(global.__snitchNetworkPendingMessages, 0, 1);
                }
            }
        }
        
        if (global.__snitchRequestBackupFailures < SNITCH_REQUEST_BACKUP_RESEND_MAX_FAILURES)
        {
            if (current_time - global.__snitchRequestBackupResendTime > SNITCH_REQUEST_BACKUP_RESEND_DELAY)
            {
                var _backupCount = array_length(global.__snitchRequestBackupOrder);
                if (_backupCount > 0)
                {
                    //Step round the request backup array
                    global.__snitchRequestBackupResendIndex = (global.__snitchRequestBackupResendIndex + 1) mod _backupCount;
                    
                    //Pull out a backup...
                    var _uuid = global.__snitchRequestBackupOrder[global.__snitchRequestBackupResendIndex];
                    with(global.__snitchRequestBackups[$ _uuid])
                    {
                        //...and if we're not waiting for a response for this particular request, resend it
                        if (asyncID < 0)
                        {
                            if (SNITCH_REQUEST_BACKUP_OUTPUT_ATTEMPT) __SnitchTrace("Trying to resend event ", _uuid);
                            
                            switch(SNITCH_INTEGRATION_MODE)
                            {
                                case 1: __SnitchGoogleAnalyticsHTTPRequest(self); break;
                                case 2: __SnitchSentryHTTPRequest(self);          break;
                                case 3: __SnitchGameAnalyticsHTTPRequest(self);   break;
                                case 4: __SnitchBugsnagHTTPRequest(self);         break;
                                case 5: __SnitchDeltaDNAHTTPRequest(self);        break;
                            }
                            
                            global.__snitchRequestBackupResendTime = current_time;
                        }
                    }
                }
            }
        }
        else
        {
            if (current_time - global.__snitchRequestBackupResendTime > SNITCH_REQUEST_BACKUP_RESEND_FAILURE_TIMEOUT)
            {
                global.__snitchRequestBackupFailures = 0;
                __SnitchTrace("Retrying backup resending");
            }
        }
    }, [], -1));
}

function __SnitchCrashSetGMHandler(_function)
{
    global.__snitchGMExceptionHandler = _function;
}

function __SnitchIntegrationName()
{
    switch(SNITCH_INTEGRATION_MODE)
    {
        case 0: return "None";             break;
        case 1: return "Google Analytics"; break;
        case 2: return "sentry.io";        break;
        case 3: return "GameAnalytics";    break;
        case 4: return "Bugsnag";          break;
        case 5: return "DeltaDNA";         break;
        
        default:
            __SnitchError("SNITCH_INTEGRATION_MODE value ", SNITCH_INTEGRATION_MODE, " unsupported");
        break;
    }
}

function __SnitchTrace()
{
    var _string = "Snitch: ";
    var _i = 0;
    repeat(argument_count)
    {
        _string += string(argument[_i]);
        ++_i;
    }
    
    SnitchSendStringToLogFile(_string);
    SnitchSendStringToNetwork(_string);
    show_debug_message(_string);
}

function __SnitchError()
{
    var _string = "";
    var _i = 0;
    repeat(argument_count)
    {
        _string += string(argument[_i]);
        ++_i;
    }
    
    show_error("Snitch:\n" + _string + "\n ", true);
}