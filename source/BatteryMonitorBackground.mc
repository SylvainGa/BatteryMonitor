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
        var prevData = Background.getBackgroundData();
        var data;
        var i;
        if (data == null) {
            data = new [1];
            i = 0;
            /*DEBUG*/ logMessage("BG no previous data ");
        }
        else {
            var size = prevData.size();
            data = new [ size + 1];
            for (i = 0; i < size; i++) {
                data[i] = prevData[i];
            }
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

        data[i] = [now, battery, solar];

        /*DEBUG*/ logMessage("BGExit " + data);
        Background.exit(data);
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
