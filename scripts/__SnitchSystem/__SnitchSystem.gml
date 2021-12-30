// GameAnalytics - https://restapidocs.gameanalytics.com/
// Google Analytics - https://developers.google.com/analytics/devguides/collection/protocol/v1/
// Log4j - https://logging.apache.org/log4j/2.x/manual/layouts.html
// sentry.io - https://develop.sentry.dev/sdk/overview/    https://develop.sentry.dev/sdk/event-payloads/https://develop.sentry.dev/sdk/event-payloads/
// Yandex AppMetrica - https://appmetrica.yandex.com/docs/mobile-api/post/post-import-events.html

//Redirect exception_unhandled_handler() to our own internal function
//The bound exception handler will still be executed
#macro  exception_unhandled_handler      __SnitchCrashSetGMHandler
#macro  __exception_unhandled_handler__  exception_unhandled_handler



#macro SNITCH_VERSION               "3.0.0"
#macro SNITCH_DATE                  "2021-12-30"
#macro SNITCH_SHARED_EVENT_PAYLOAD  global.__snitchSharedEventPayload
#macro SNITCH_OS_NAME               global.__snitchOSName
#macro SNITCH_OS_VERSION            global.__snitchOSVersion
#macro SNITCH_DEVICE_NAME           global.__snitchDeviceName
#macro SNITCH_BROWSER               global.__snitchBrowser
#macro SNITCH_OS_INFO               global.__snitchOSInfo
#macro SNITCH_BOOT_PARAMETERS       global.__snitchBootParameters
#macro __SNITCH_HTTP_NEEDED         (SNITCH_GOOGLE_ANALYTICS_PERMITTED || SNITCH_SENTRY_PERMITTED || SNITCH_GAMEANALYTICS_PERMITTED)



//Initialize the library
__SnitchInit();

function __SnitchInit()
{
    //Don't initialize twice
    if (variable_global_exists("__snitchLogToFileEnabled")) return;
    
    global.__snitchGMExceptionHandler = undefined;
    
    global.__snitchLogToFileEnabled       = false;
    global.__snitchGoogleAnalyticsEnabled = false;
    global.__snitchSentryEnabled          = false;
    global.__snitchGameAnalyticsEnabled   = false;
    global.__snitchUDPEnabled             = false;
    
    //Log files
    global.__snitchWroteLogFileHeader = false;
    global.__snitchZerothLogFile      = string_replace(SNITCH_LOG_FILE_FILENAME, "#", "0");
    global.__snitchLogFileBuffer      = buffer_create(SNITCH_LOG_FILE_BUFFER_START_SIZE, buffer_grow, 1);
    
    //HTTP-related tracking
    global.__snitchHTTPHeaderMap               = ds_map_create(); //Has to be a map due to GameMaker's HTTP request API
    global.__snitchHTTPRequests                = {};
    global.__snitchRequestBackups              = {};
    global.__snitchRequestBackupOrder          = [];
    global.__snitchRequestBackupManifestBuffer = buffer_create(512, buffer_grow, 1);
    global.__snitchRequestBackupResendTime     = -SNITCH_REQUEST_BACKUP_RESEND_DELAY; //Try to send a request backup immediately on boot
    global.__snitchRequestBackupResendIndex    = 0;
    global.__snitchRequestBackupFailures       = 0;
    
    global.__snitchMessageBuffer    = buffer_create(1024, buffer_grow, 1);
    global.__snitchMessageTellArray = [];
    global.__snitchMessageRead      = false;
    global.__snitchMessageString    = "";
    
    
    
    //Build an array for the boot parameters
    SNITCH_BOOT_PARAMETERS = [];
    var _i = 0;
    repeat(parameter_count())
    {
        array_push(SNITCH_BOOT_PARAMETERS,  parameter_string(_i));
        ++_i;
    }
    
    
    
    #region Set SNITCH_OS_NAME, SNITCH_OS_VERSION, SNITCH_DEVICE_NAME, SNITCH_BROWSER, SNITCH_OS_INFO
        
    SNITCH_OS_NAME     = "Unknown (=" + string(os_type) + ")"
    SNITCH_OS_VERSION  = "Unknown (=" + string(os_version) + ")"
    SNITCH_DEVICE_NAME = global.__snitchOSName + " " + global.__snitchOSVersion;
    SNITCH_BROWSER     = "Unknown browser";
    
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
            
            SNITCH_DEVICE_NAME = SNITCH_OS_NAME + " " + SNITCH_OS_VERSION;
        break;
        
        case os_uwp:
            SNITCH_OS_NAME     = "UWP";
            SNITCH_OS_VERSION  = string(os_version);
            SNITCH_DEVICE_NAME = SNITCH_OS_NAME + " " + SNITCH_OS_VERSION;
        break;
        
        case os_linux:
            SNITCH_OS_NAME     = "Linux";
            SNITCH_OS_VERSION  = string(os_version);
            SNITCH_DEVICE_NAME = SNITCH_OS_NAME + " " + SNITCH_OS_VERSION;
        break;
        
        case os_macosx:
            SNITCH_OS_NAME     = "Mac OS X";
            SNITCH_OS_VERSION  = string(os_version >> 24) + "." + string((os_version >> 12) & 0xfff);
            SNITCH_DEVICE_NAME = SNITCH_OS_NAME + " " + SNITCH_OS_VERSION;
        break;
        
        case os_ios:
            SNITCH_OS_NAME     = "iOS";
            SNITCH_OS_VERSION  = string(os_version >> 24) + "." + string((os_version >> 12) & 0xfff);
            SNITCH_DEVICE_NAME = SNITCH_OS_NAME + " " + SNITCH_OS_VERSION;
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
                case 27: SNITCH_OS_VERSION = "v10";         break;
                case 28: SNITCH_OS_VERSION = "v11";         break;
                case 29: SNITCH_OS_VERSION = "v12";         break;
            }
            
            SNITCH_DEVICE_NAME = SNITCH_OS_NAME + " " + SNITCH_OS_VERSION;
        break;
        
        case os_ps3:     SNITCH_OS_NAME = "PlayStation 3";    break;
        case os_ps4:     SNITCH_OS_NAME = "PlayStation 4";    break;
        case os_psvita:  SNITCH_OS_NAME = "PlayStation Vita"; break;
        case os_xboxone: SNITCH_OS_NAME = "Xbox One";         break;
        case os_switch:  SNITCH_OS_NAME = "Switch";           break;
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
    if (os_browser != browser_not_a_browser) SNITCH_DEVICE_NAME = SNITCH_BROWSER;
    
    //Turn the os_get_info() map into a struct for serialization
    SNITCH_OS_INFO = {};
    var _infoMap = os_get_info();
    var _key = ds_map_find_first(_infoMap);
    repeat(ds_map_size(_infoMap))
    {
        SNITCH_OS_INFO[$ _key] = _infoMap[? _key];
        _key = ds_map_find_next(_infoMap, _key);
    }
    ds_map_destroy(_infoMap);
    
    #endregion
    
    
    
    if (SNITCH_LOG_FILE_ON_BOOT) SnitchLogFileSet(true);
    __SnitchTrace("Welcome to Snitch by @jujuadams! This is version " + string(SNITCH_VERSION) + ", " + string(SNITCH_DATE));
    
    if (SNITCH_CRASH_CAPTURE)
    {
        __exception_unhandled_handler__(__SnitchExceptionHandler);
    }
    
    if (SNITCH_REQUEST_BACKUP_COUNT < 1)
    {
        __SnitchError("SNITCH_REQUEST_BACKUP_COUNT must be greater than zero");
    }
    
    if (SNITCH_ALLOW_LOG_FILE_BOOT_PARAMETER && (os_type == os_windows))
    {
        var _i = 0;
        repeat(parameter_count())
        {
            if (parameter_string(_i) == "-log")
            {
                SnitchLogFileSet(true);
                if (SnitchLogFileGet() && (SNITCH_LOG_FILE_BOOT_PARAMETER_CONFIRMATION != "")) show_message(SNITCH_LOG_FILE_BOOT_PARAMETER_CONFIRMATION);
                break;
            }
            
            _i++;
        }
    }
    
    
    
    if (SNITCH_GOOGLE_ANALYTICS_PERMITTED + SNITCH_SENTRY_PERMITTED + SNITCH_GAMEANALYTICS_PERMITTED > 1)
    {
        __SnitchError("Only one monitoring integration can be enabled at a time\nSNITCH_GOOGLE_ANALYTICS_PERMITTED = ", SNITCH_GOOGLE_ANALYTICS_PERMITTED, "\nSNITCH_SENTRY_PERMITTED = ", SNITCH_SENTRY_PERMITTED, "\nSNITCH_GAMEANALYTICS_PERMITTED = ", SNITCH_GAMEANALYTICS_PERMITTED);
    }
    
    
    
    //Create the shared event payload
    SNITCH_SHARED_EVENT_PAYLOAD = __SnitchSentrySharedEventPayload();
    
    if (SNITCH_REQUEST_BACKUP_ENABLE && __SNITCH_HTTP_NEEDED)
    {
        var _loadedManifest = false;
        try
        {
            var _buffer = buffer_load(SNITCH_REQUEST_BACKUP_MANIFEST_FILENAME);
            _loadedManifest = true;
            
            var _json = buffer_read(_buffer, buffer_string);
            global.__snitchRequestBackupOrder = json_parse(_json);
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
    
    
    
    if (SNITCH_SENTRY_PERMITTED)
    {
        //Force a network connection if possible
        os_is_network_connected(true);
        
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
        
        global.__snitchSentryEndpoint = _protocol + "://" + _DSNHostPath + "/api/" + _DSNProject + "/store/";
        
        //Build an auth string for later HTTP requests
        //We fill in the timestamp later when sending the request
        global.__snitchSentryAuthString = "Sentry sentry_version=7, sentry_client=Snitch/" + string(SNITCH_VERSION) + ", sentry_key=" + global.__snitchSentryPublicKey + ", sentry_timestamp=";
        
        if (debug_mode)
        {
            __SnitchTrace("Sentry public key = \"", global.__snitchSentryPublicKey, "\"");
            __SnitchTrace("Sentry endpoint = \"", global.__snitchSentryEndpoint, "\"");
        }
    }
    
    if (SNITCH_GOOGLE_ANALYTICS_ON_BOOT) SnitchGoogleAnalyticsSet(true);
    if (SNITCH_SENTRY_ON_BOOT) SnitchSentrySet(true);
    if (SNITCH_GAMEANALYTICS_ON_BOOT) SnitchGameAnalyticsSet(true);
}

function __SnitchCrashSetGMHandler(_function)
{
    global.__snitchGMExceptionHandler = _function;
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

#macro SnitchMessageStartArgument  __SnitchInit();\
                                  var _snitchMessageBuffer    = global.__snitchMessageBuffer;\
                                  var _snitchMessageTellArray = global.__snitchMessageTellArray;\
                                  global.__snitchMessageRead = false;\
                                  buffer_seek(_snitchMessageBuffer, buffer_seek_start, 0);\
                                  array_resize(_snitchMessageTellArray, 0);\\
                                  var _i = 0;\
                                  repeat(argument_count)\
                                  {\
                                      array_push(_snitchMessageTellArray, buffer_tell(_snitchMessageBuffer));\
                                      buffer_write(_snitchMessageBuffer, buffer_text, argument[_i]);\
                                      ++_i;\
                                  }\
                                  buffer_write(_snitchMessageBuffer, buffer_u8, 0x00);\
                                  var _snitchMessageStartIndex

#macro SnitchMessage  __SnitchMessageString(_snitchMessageStartIndex)

function __SnitchMessageString(_startIndex)
{
    __SnitchInit();
    
    if (!global.__snitchMessageRead)
    {
        global.__snitchMessageRead = true;
        buffer_seek(global.__snitchMessageBuffer, buffer_seek_start, global.__snitchMessageTellArray[_startIndex]);
        global.__snitchMessageString = buffer_read(global.__snitchMessageBuffer, buffer_string);
    }
    
    return global.__snitchMessageString;
}