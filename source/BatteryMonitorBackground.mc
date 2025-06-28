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
        var stats = Sys.getSystemStats();
	    var battery = stats.battery;//.toNumber();// out of 100
	    var now = Time.now().value(); //in seconds from UNIX epoch in UTC
        Background.exit([now, now, battery]);
    }
}

function getData(){
    var stats = Sys.getSystemStats();
    var battery = stats.battery;//.toNumber();// out of 100
    var now = Time.now().value(); //in seconds from UNIX epoch in UTC
    return [now, now, battery];
}
