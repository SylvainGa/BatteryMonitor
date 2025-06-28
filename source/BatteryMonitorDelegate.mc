using Toybox.WatchUi as Ui;
using Toybox.System as Sys;
using Toybox.Timer;
using Toybox.Application as App;
using Toybox.Time;
using Toybox.Time.Gregorian;
using Toybox.Graphics as Gfx;

class BatteryMonitorInitDelegate extends Ui.InputDelegate{
	
	function initialize(){
        InputDelegate.initialize();
	}
	
	function goBack(){
		return false;
    }

    function onSelect(){
		analyzeAndStoreData(getData());
        Ui.requestUpdate();
        return true;    
    }
	
    function onTap(evt) {
		onSelect();
		return true;
    }

    function onNextPage() {
		gViewScreen++;
		if (gViewScreen > SCREEN_PROJECTION) {
			gViewScreen = SCREEN_DATA_HR;
		}
        Ui.requestUpdate();
		return true;
	}

    function onPreviousPage() {
		gViewScreen--;
		if (gViewScreen < SCREEN_DATA_HR) {
			gViewScreen = SCREEN_PROJECTION;
		}
        Ui.requestUpdate();
		return true;
	}

	function onSwipe(swipeEvent) {
		if (swipeEvent.getDirection() == WatchUi.SWIPE_DOWN) {
			onPreviousPage();
			return true;
		}

		if (swipeEvent.getDirection() == WatchUi.SWIPE_UP) {
			onNextPage();
			return true;
		}

		return false;
	}

    function onMenu() {
        var dialog = new Ui.Confirmation("Erase history");
        Ui.pushView(dialog, new ConfirmationDialogDelegate(), Ui.SLIDE_IMMEDIATE);
        return true;
    }
    
    function onKey(evt) {
    	if (evt.getKey() == Ui.KEY_ENTER){
			onSelect();
			return true;
    	}
    	
    	if (evt.getKey() == Ui.KEY_MENU){
    		return onMenu();
    	}
    	
		return false;
    }
}

class ConfirmationDialogDelegate extends Ui.ConfirmationDelegate {
    function initialize() {
        ConfirmationDelegate.initialize();
    }

    function onResponse(value) {
        if (value == 0) {
			//Keep
        }
        else {
            //Erase
            objectStoreErase("HISTORY_KEY");
            objectStoreErase("LAST_HISTORY_KEY");
            objectStoreErase("COUNT");
            objectStoreErase("LAST_VIEWED_DATA");
            objectStoreErase("LAST_CHARGED_DATA");
        }
		return true;
    }
}
