using Toybox.Background;
using Toybox.System as Sys;
using Toybox.Time;

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
            /*DEBUG*/ logMessage("onTemporalEvent: BG no previous data ");
        }
        else {
            /*DEBUG*/ logMessage("onTemporalEvent: BG previous data " + data);
        }

        var stats = Sys.getSystemStats();
        var battery = (stats.battery * 10).toNumber(); // * 10 to keep one decimal place without using the space of a float variable
        var solar = (stats.solarIntensity == null ? null : stats.solarIntensity >= 0 ? stats.solarIntensity : 0);
        var now = Time.now().value(); //in seconds from UNIX epoch in UTC

        if (Sys.getSystemStats().charging) {
            var chargingData = objectStoreGet("STARTED_CHARGING_DATA", null);
            if (chargingData == null) {
                objectStorePut("STARTED_CHARGING_DATA", [now, battery, solar]);
            }
        }
        else {
            objectStoreErase("STARTED_CHARGING_DATA");
        }

        // Only add if it's newer to prevent passing data that are not going to be consumed
        var dataSize = data.size();
        if (dataSize == 0 || data[dataSize - 1][BATTERY] != battery) {
            data.add([now, battery, solar]);

            var success;
            do {
                /*DEBUG*/ logMessage("onTemporalEvent: Exit " + data);
                success = true; // Assume we'll succeed
                try {
                    Background.exit(data);
                }
                catch (e instanceof Background.ExitDataSizeLimitException) { // We are trying to pass to much data! Shrink it down!
                    success = false; // We didn't :-( Half the data and retry
                    var newSize = data.size() / 2;
                    var retryData = new [newSize];
                    
                    for (var i = 0; i < newSize; i++) {
                        retryData[i] = data[i * 2]; // Mo averaging, here, just take every second data. We've been away from the app for very long, no need to be this precise.
                    }
                    /*DEBUG*/ logMessage("onTemporalEvent: Exit failed. Had " + (newSize * 2) + " elements. Retrying with just " + newSize + " elements" + data);
                    data = retryData;
                }
            } while (success == false);
        }
        else {
            /*DEBUG*/ logMessage("onTemporalEvent: Exit ignoring " + battery);
            Background.exit(null);
        }
    }
}
