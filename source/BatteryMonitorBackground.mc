using Toybox.Background;
using Toybox.Activity;
using Toybox.System as Sys;
using Toybox.Time;
using Toybox.Lang;

// The Service Delegate is the main entry point for background processes
// our onTemporalEvent() method will get run each time our periodic event
// is triggered by the system. This indicates a set timer has expired, and
// we should attempt to notify the user.
(:background)
class BatteryMonitorServiceDelegate extends Sys.ServiceDelegate {
    function initialize() {
        ServiceDelegate.initialize();
    }

    // If our timer expires, it means the application timer ran out,
    // and the main application is not open. Prompt the user to let them
    // know the timer expired.
    function onTemporalEvent() {
        var data = Background.getBackgroundData();
        if (data == null) {
            data = [];
            //DEBUG*/ logMessage("onTE: BG no previous data ");
        }
        else {
            //DEBUG*/ logMessage("onTE: BG previous data (" + data.size() + ") last: " + data[data.size() - 1]);
            if (data[0] instanceof Toybox.Lang.Array) {
                data = []; // If we have the old array format, drop it. Yeah, sucks but no point to add code just for one time when space is already limited
            }
        }

        var now = Time.now().value(); //in seconds from UNIX epoch in UTC
        var stats = Sys.getSystemStats();
        var battery = (stats.battery * 10).toNumber(); // * 10 to keep one decimal place without using the space of a float variable
        var solar = (stats.solarIntensity == null ? null : stats.solarIntensity >= 0 ? stats.solarIntensity : 0);

        var nowData = [now, battery, solar];

        if (Sys.getSystemStats().charging) {
            var chargingData = $.objectStoreGet("STARTED_CHARGING_DATA", null);
            if (chargingData == null) {
                $.objectStorePut("STARTED_CHARGING_DATA", nowData);
            }
            $.objectStorePut("LAST_CHARGE_DATA", nowData);
        }
        else {
            $.objectStoreErase("STARTED_CHARGING_DATA");
        }

        // Flag if an activity is currently going
        var activityStartTime = Activity.getActivityInfo().startTime;
        if (activityStartTime != null) { // we"ll hack the battery level to flag the start and end of the activity. We'll 'or' 4096 (0x1000) to the battery level to flag when an activity is running.
            nowData[BATTERY] |= 0x1000;
        }

        // Only add if it's newer to prevent passing data that are not going to be consumed
        var dataSize = data.size();
        if (dataSize == 0 || data[dataSize - 3 + BATTERY] != nowData[BATTERY]) { // We use '3' here and not elementSize as data is ALWAYS three fields (TIMESTANP, BATTERY AND SOLAR)
            data.addAll(nowData);
            //DEBUG*/ logMessage("TE: " + nowData);

            var success;

            //DEBUG*/  data = new [2001]; for (var i = 0; i < 2001; i++) {  data[i] = i; }

            do {
                /*DEBUG*/ logMessage("onTE: Exit with " + (dataSize / 3) + " elements");
                success = true; // Assume we'll succeed
                try {
                    Background.exit(data);
                }
                catch (e instanceof Background.ExitDataSizeLimitException) { // We are trying to pass too much data! Shrink it down!
                    /*DEBUG*/ logMessage("Exit failed.");
                    success = false; // We didn't :-( Half the data and retry
                    dataSize = (data.size() / 2); // Doing it this way so precision error doesn't truncate it too short
                    for (var i = 0; i < dataSize; i += 3) {  // No averaging, here, just take every second data. We've been away from the app for very long, no need to be this precise.
                        var j = i * 2;
                        data[i + TIMESTAMP] = data[j + TIMESTAMP];
                        data[i + BATTERY] =   data[j + BATTERY];
                        data[i + SOLAR] =     data[j + SOLAR];
                    }

                    /*DEBUG*/ logMessage("Had " + ((dataSize * 2) / 3) + " elements. Retrying with just " + (dataSize / 3) + " elements");
                    data = data.slice(0, dataSize);
                }
            } while (success == false);
        }
        else {
            //DEBUG*/ logMessage("onTE: Exit ignoring " + battery);
            Background.exit(null);
        }
    }
}
