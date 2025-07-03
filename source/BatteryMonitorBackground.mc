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
        var i;
        var data = Background.getBackgroundData();
        if (data == null) {
            data = [];
            /*DEBUG*/ logMessage("BG no previous data ");
        }
        else {
            /*DEBUG*/ logMessage("BG previous data " + data);
        }

        var stats = Sys.getSystemStats();
        var battery = (stats.battery * 1000).toNumber(); // * 1000 to keep three digits after the dot without using the space of a float variable
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

        data.add([now, battery, solar]);

        /*DEBUG*/ logMessage("BGExit " + data);
        try {
            Background.exit(data);
        }
        catch (e instanceof Background.ExitDataSizeLimitException) { // We are trying to pass to much data! Shrink it down!
            var size = data.size();
            var sizeInBytes = data[0].size() * 4 + 15; // 32 bits elements is 4 bytes. data[0] could be made of 2 or 3 32 bits elements and each element has an overhead of 15 byes! 
            var newSize = size * 8000 / sizeInBytes; // 8000 is the maximum size in bytes that can be passed
            var retryData = new [newSize];
            var j;
            for (i = size - newSize, j = 0; i < size; i++, j++) {
                retryData[j] = data[i];
            }
            /*DEBUG*/ logMessage("BGExit failed. Had " + size + " elements. Retrying with just " + newSize + " elements" + data);
            Background.exit(retryData);
        }
    }
}

function getData(){
    var stats = Sys.getSystemStats();
    var battery = (stats.battery * 1000).toNumber(); // * 1000 to keep three digits after the dot without using the space of a float variable
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

    return [now, battery, solar];
}
