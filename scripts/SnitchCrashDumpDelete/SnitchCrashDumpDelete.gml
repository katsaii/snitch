/// Deletes the last crash dump from disk

function SnitchCrashDumpDelete()
{
    __SnitchInit();
    
    if ((SNITCH_CRASH_DUMP_FILENAME != "") && file_exists(SNITCH_CRASH_DUMP_FILENAME)) file_delete(SNITCH_CRASH_DUMP_FILENAME);
}