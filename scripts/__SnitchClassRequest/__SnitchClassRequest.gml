function __SnitchClassRequest(_uuid, _string) constructor
{
    content     = _string;
    UUID        = _uuid;
    savedBackup = false;
    
    asyncID      = -1;
    responseCode = 0;
    status       = 0;
    
    static __Send = function(_url, _method, _headerMap, _compress)
    {
        if (os_is_network_connected(false))
        {
            if (_compress)
            {
                //Fire off the HTTP request using the appropriate encoding
                asyncID = http_request(_url, _method, _headerMap, __GetCompressedString());
            }
            else
            {
                //If we don't want to compress our HTTP request, use the raw content
                asyncID = http_request(_url, _method, _headerMap, content);
            }
            
            if (asyncID >= 0)
            {
                //If the HTTP request is valid then link the returned ID to this struct for use later
                global.__snitchHTTPRequests[$ string(asyncID)] = self;
            }
            else
            {
                //Otherwise immediately trigger a failed HTTP response
                __HTTPResponse(-1, -1);
            }
        }
    }
    
    static __GetCompressedString = function()
    {
        //If we want to compress the buffer, do the ol' swaperoo
        var _buffer = buffer_create(string_byte_length(content), buffer_fixed, 1);
        buffer_write(_buffer, buffer_text, content);
        var _compressedBuffer = buffer_compress(_buffer, 0, buffer_get_size(_buffer));
        
        var _string = buffer_base64_encode(_compressedBuffer, 0, buffer_get_size(_compressedBuffer));
        
        //Clean up!
        buffer_delete(_buffer);
        buffer_delete(_compressedBuffer);
        
        return _string;
    }
    
    static __SaveBackup = function()
    {
        //Don't bother saving a backup if there's no buffer to save, we've already saved a backup, or we never want to save any backups at all
        if (savedBackup || !SNITCH_REQUEST_BACKUP_ENABLE) return undefined;
        
        //Add the request to our tracking data structures
        global.__snitchRequestBackups[$ UUID] = self;
        array_push(global.__snitchRequestBackupOrder, UUID);
        
        //If we've exceeded our maximum number of backups, delete a few until we're back within limits
        repeat(array_length(global.__snitchRequestBackupOrder) - SNITCH_REQUEST_BACKUP_COUNT)
        {
            global.__snitchRequestBackupOrder[0].__Destroy();
        }
        
        //Make sure the manifest is updated on disk
        __SnitchRequestBackupSaveManifest();
        
        //Actually do the saving
        var _buffer = buffer_create(string_byte_length(content), buffer_fixed, 1);
        buffer_write(_buffer, buffer_text, content);
        buffer_save(_buffer, __SnitchRequestBackupFilename(UUID));
        buffer_delete(_buffer);
        
        savedBackup = true;
    }
    
    static __HTTPResponse = function(_responseCode, _status)
    {
        responseCode = _responseCode;
        status       = _status;
        
        if ((responseCode == 200) || (responseCode == 204))
        {
            if (SNITCH_OUTPUT_HTTP_SUCCESS) __SnitchTrace("Request ", UUID, " complete (HTTP ", responseCode, ")");
            __Destroy();
            
            //Reset the failure count
            global.__snitchRequestBackupFailures = 0;
        }
        else if (status != 1)
        {
            __SnitchTrace("Request ", UUID, " failed (HTTP ", responseCode, ")");
            
            if (responseCode == 400)
            {
                __SnitchTrace("Warning! Response was \"HTTP 400 - Bad Request\". Check your event payload");
                __Destroy();
            }
            else if (global.__snitchRequestBackupFailures < SNITCH_REQUEST_BACKUP_RESEND_MAX_FAILURES)
            {
                //Increment the failure count
                global.__snitchRequestBackupFailures++;
                
                if (global.__snitchRequestBackupFailures >= SNITCH_REQUEST_BACKUP_RESEND_MAX_FAILURES)
                {
                    __SnitchTrace("Too many failed requests (", global.__snitchRequestBackupFailures, "), retrying later");
                }
            }
        }
        else
        {
            //Pending, do nothing
        }
    }
    
    static __Destroy = function()
    {
        //Remove ourselves from the HTTP request lookup
        variable_struct_remove(global.__snitchHTTPRequests, asyncID);
        
        //Delete any backup on disk
        file_delete(__SnitchRequestBackupFilename(UUID));
        
        //Remove this request from our backup records
        variable_struct_remove(global.__snitchRequestBackups, UUID);
        var _i = array_length(global.__snitchRequestBackupOrder) - 1
        repeat(_i + 1)
        {
            if (global.__snitchRequestBackupOrder[_i] == UUID) array_delete(global.__snitchRequestBackupOrder, _i, 1);
            --_i;
        }
    }
}

function __SnitchRequestBackupFilename(_uuid)
{
    return string_replace(SNITCH_REQUEST_BACKUP_FILENAME, "#", _uuid);
}

function __SnitchRequestBackupSaveManifest()
{
    static _buffer = buffer_create(1024, buffer_grow, 1);
    buffer_seek(_buffer, buffer_seek_start, 0);
    buffer_write(_buffer, buffer_text, json_stringify(global.__snitchRequestBackupOrder));
    buffer_save_ext(_buffer, SNITCH_REQUEST_BACKUP_MANIFEST_FILENAME, 0, buffer_tell(_buffer));
}

function __SnitchSentryHTTPRequest(_request)
{
    //Set up the headers...
    global.__snitchHTTPHeaderMap[? "Content-Type" ] = "application/json";
    global.__snitchHTTPHeaderMap[? "X-Sentry-Auth"] = global.__snitchSentryAuthString + string(SnitchConvertToUnixTime(date_current_datetime()));
    
    //And fire off the request!
    //Good luck little packet
    _request.__Send(global.__snitchEndpoint, "POST", global.__snitchHTTPHeaderMap, true);
    
    ds_map_clear(global.__snitchHTTPHeaderMap);
}

function __SnitchGameAnalyticsHTTPRequest(_request)
{
    // "The authentication value is a HMAC SHA-256 digest of the raw body content from the request using the secret key (private key) as the hashing key and then encoding it using base64."
    var _hashArray = __SnitchHMACSHA256(SNITCH_GAMEANALYTICS_SECRET_KEY, _request.content, false);
    
    //Get the base64 encoded version of the digest, whilst also handling endianness conversion
    var _hashBuffer = buffer_create(64, buffer_fixed, 1);
    var _i = 0;
    repeat(8)
    {
        var _u32 = _hashArray[_i];
        buffer_write(_hashBuffer, buffer_u8, (_u32 >> 24) & 0xFF);
        buffer_write(_hashBuffer, buffer_u8, (_u32 >> 16) & 0xFF);
        buffer_write(_hashBuffer, buffer_u8, (_u32 >>  8) & 0xFF);
        buffer_write(_hashBuffer, buffer_u8, (_u32      ) & 0xFF);
        ++_i;
    }
    
    var _authHash = buffer_base64_encode(_hashBuffer, 0, 32);
    buffer_delete(_hashBuffer);
    
    //Set up the header...
    global.__snitchHTTPHeaderMap[? "Authorization"] = _authHash;
    global.__snitchHTTPHeaderMap[? "Content-Type" ] = "application/json";
    
    _request.__Send(global.__snitchEndpoint, "POST", global.__snitchHTTPHeaderMap, false);
    
    ds_map_clear(global.__snitchHTTPHeaderMap);
}

function __SnitchBugsnagHTTPRequest(_request)
{
    //Set up the header...
    global.__snitchHTTPHeaderMap[? "Content-Type"           ] = "application/json";
    global.__snitchHTTPHeaderMap[? "Bugsnag-Api-Key"        ] = SNITCH_BUGSNAG_API_KEY;
    global.__snitchHTTPHeaderMap[? "Bugsnag-Payload-Version"] = "5";
    
    _request.__Send("https://notify.bugsnag.com", "POST", global.__snitchHTTPHeaderMap, false);
    
    ds_map_clear(global.__snitchHTTPHeaderMap);
}

function __SnitchDeltaDNAHTTPRequest(_request)
{
    //Set up the header...
    global.__snitchHTTPHeaderMap[? "Content-Type"] = "application/json";
    
    var _url = global.__snitchEndpoint;
    if (SNITCH_DELTADNA_SECRET_KEY != "") _url += md5_string_unicode(_request.content + SNITCH_DELTADNA_SECRET_KEY);
    _request.__Send(_url, "POST", global.__snitchHTTPHeaderMap, false);
    
    ds_map_clear(global.__snitchHTTPHeaderMap);
}