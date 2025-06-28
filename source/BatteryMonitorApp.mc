using Toybox.Application as App;
using Toybox.Background;
using Toybox.System as Sys;
using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.Application.Storage;

//! App constants
const HISTORY_MAX = 500; // 5000 points = 5 times a full discharge
const INTERVAL_MIN = 60;//temporal event in minutes

//! Object store keys (now they keys are in Storage and are texts, not numbers)
// const HISTORY_KEY = 2;
// const LAST_HISTORY_KEY = 3;
// const COUNT = 1;
// const LAST_VIEWED_DATA = 4;
// const LAST_CHARGED_DATA = 5;

const COLOR_BAT_OK = Gfx.COLOR_GREEN;
const COLOR_BAT_LOW = Gfx.COLOR_YELLOW;
const COLOR_BAT_CRITICAL = Gfx.COLOR_RED;
const COLOR_PROJECTION = Gfx.COLOR_DK_BLUE;

const SCREEN_DATA = 1;
const SCREEN_HISTORY = 2;
const SCREEN_PROJECTION = 3;

//! History Array data type
enum{
	TIMESTAMP_START,
	TIMESTAMP_END,
	BATTERY,
	FREEMEMORY
}

var gAbleBackground = false;
var gViewScreen = SCREEN_DATA;

(:background)
class BatteryMonitorApp extends App.AppBase {
    var mGlanceView;
    
    function initialize() {
        AppBase.initialize();
    }

    // onStart() is called on application start up
    function onStart(state) {
    	//objectStorePut("HISTORY_KEY",null);
    }

    // onStop() is called when your application is exiting
    function onStop(state) {
    }

    (:glance)
    function getGlanceView() {
    	if (Toybox.System has :ServiceDelegate) {
            gAbleBackground = true;
            Background.registerForTemporalEvent(new Time.Duration(INTERVAL_MIN * 60));//x mins - total in seconds
        }
        mGlanceView = new BatteryMonitorGlanceView();
        return [ mGlanceView ];
    }

    // Return the initial view of your application here
    function getInitialView() {	
    	//Sys.println("App/getInitialView");
    	//register for temporal events if they are supported
    	if (Toybox.System has :ServiceDelegate) {
    		gAbleBackground = true;
    		Background.registerForTemporalEvent(new Time.Duration(INTERVAL_MIN * 60));//x mins - total in seconds
    	}
        return [ new BatteryMonitorView() , new BatteryMonitorInitDelegate() ];
    }
    
    function getServiceDelegate(){
    	//Sys.println("App/getServiceDelegate");
        return [new BatteryMonitorServiceDelegate()];
    }

    function onBackgroundData(data) {
    	//Sys.println("App/onBackgroundData");
    	//Sys.println("data received " + data);
		analyzeAndStoreData(data);    	
        Ui.requestUpdate();
    }    
}

(:background)
function analyzeAndStoreData(data){
	//Sys.println("analyzeAndStoreData");
	var lastHistory = objectStoreGet("LAST_HISTORY_KEY", null);
	if (lastHistory == null){ // no data yet
		objectStoreAdd("HISTORY_KEY", data);
	}
	else { //data already exists
		if (lastHistory[BATTERY] == data[BATTERY]){
			var history = objectStoreGet("HISTORY_KEY", null);
			if (history != null) {
				history[history.size() - 1][TIMESTAMP_END] = data[TIMESTAMP_END];
				objectStorePut("HISTORY_KEY", history);
			}
		}
		else {
			objectStoreAdd("HISTORY_KEY", data);
		}
	}
	objectStorePut("LAST_HISTORY_KEY", data);
	objectStorePut("COUNT", objectStoreGet("COUNT", 0) + 1);
}

// Global method for getting a key from the object store
// with a specified default. If the value is not in the
// store, the default will be saved and returned.
(:background)
function objectStoreAdd(key, newValue) {
    //Sys.println("objectStoreAdd");
    var existingArray = objectStoreGet(key, []);
    if (newValue != null) {
    	if (!(existingArray instanceof Toybox.Lang.Array)) {//if not array (incl is null), then create first item of array
	        objectStorePut(key, [newValue]);
	    }
		else { //existing value is an array -> append data to array end
			if (existingArray.size() > HISTORY_MAX){
				objectStorePut(key, existingArray.slice(1, HISTORY_MAX - 1).add(newValue));
			}
			else {
				if (existingArray.size() < HISTORY_MAX){
		        	objectStorePut(key, existingArray.add(newValue));
				}
				else {
					objectStorePut(key, existingArray.slice(1, existingArray.size()).add(newValue));
				}
			}
	    }
	}
}

// Global method for getting a key from the object store
// with a specified default. If the value is not in the
// store, the default will be saved and returned.
(:background)
function objectStoreGet(key, defaultValue) {
    //Sys.println("objectStoreGet");
    var value = Storage.getValue(key);
    if ((value == null) && (defaultValue != null)) {
        value = defaultValue;
        Storage.setValue(key, value);
	}
    return value;
}

// Global method for putting a key value pair into the
// object store. This method doesn't do anything that
// setProperty doesn't do, but provides a matching function
// to the objectStoreGet method above.
(:background)
function objectStorePut(key, value) {
    //Sys.println("objectStorePut");
    Storage.setValue(key, value);
}

(:background)
function objectStoreErase(key) {
    //Sys.println("objectStorePut");
    Storage.deleteValue(key);
}