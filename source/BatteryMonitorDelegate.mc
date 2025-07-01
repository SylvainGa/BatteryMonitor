using Toybox.WatchUi as Ui;
using Toybox.System as Sys;
using Toybox.Timer;
using Toybox.Application as App;
using Toybox.Time;
using Toybox.Time.Gregorian;
using Toybox.Graphics as Gfx;

class BatteryMonitorDelegate extends Ui.BehaviorDelegate {
	var mView;
	var mHandler;
	
	function initialize(view, handler) {
		mView = view;
		mHandler = handler;

        BehaviorDelegate.initialize();
	}
	
	function goBack() {
		return false;
    }

    function onSelect() {
		analyzeAndStoreData(getData());

        onNextPage();
        return true;    
    }
	
    function onTap(evt) {
		// onSelect();
        onNextPage();
		return true;
    }

    function onNextPage() {
        var viewScreen = mView.getViewScreenChoice();

		viewScreen++;
		if (viewScreen > SCREEN_PROJECTION) {
			viewScreen = SCREEN_DATA_MAIN;
		}
        mHandler.invoke(viewScreen);

		return true;
	}

    function onPreviousPage() {
        var viewScreen = mView.getViewScreenChoice();

		viewScreen--;
		if (viewScreen < SCREEN_DATA_MAIN) {
			viewScreen = SCREEN_PROJECTION;
		}
        mHandler.invoke(viewScreen);

		return true;
	}

	function onSwipe(swipeEvent) {
		if (swipeEvent.getDirection() == WatchUi.SWIPE_DOWN) {
			onPreviousPage();
		}

		if (swipeEvent.getDirection() == WatchUi.SWIPE_UP) {
			onNextPage();
		}

		if (swipeEvent.getDirection() == WatchUi.SWIPE_LEFT) {
			onNextPage();
		}

		return true;
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
