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
    var mDragStartX;
    var mDragStartY;

	function initialize(view, handler) {
		mView = view;
		mHandler = handler;

        BehaviorDelegate.initialize();
	}
	
    function onSelect() {
		//DEBUG*/ $.analyzeAndStoreData([$.getData()], 1);

		if (System.getSystemStats().charging) {
	        mHandler.invoke(-1, 0);
		}
		else {
	        mHandler.invoke(mView.getPanelIndex(), 1);
		}
        return true;    
    }
	
    function onTap(evt) {
		onSelect();
		return true;
    }

    function onNextPage() {
        var panelIndex = mView.getPanelIndex();

		panelIndex++;
		if (panelIndex >= mView.getPanelSize()) {
			panelIndex = 0;
		}
        mHandler.invoke(panelIndex, 0);

		return true;
	}

    function onPreviousPage() {
        var panelIndex = mView.getPanelIndex();

		panelIndex--;
		if (panelIndex < 0) {
			panelIndex = mView.getPanelSize() - 1;
		}
        mHandler.invoke(panelIndex, 0);

		return true;
	}

	function onKey(keyEvent) {
		var key = keyEvent.getKey();
    	if (key == Ui.KEY_ENTER){
			onSelect();
			return true;
    	}
    	
    	if (key == Ui.KEY_MENU){
    		return onMenu();
    	}
    	
		return false;
	}

	function onSwipe(swipeEvent) {
		if (swipeEvent.getDirection() == WatchUi.SWIPE_DOWN) {
			onPreviousPage();
		}

		if (swipeEvent.getDirection() == WatchUi.SWIPE_UP) {
			onNextPage();
		}

		return true;
	}

    function onMenu() {
        var dialog = new Ui.Confirmation("Erase history");
        Ui.pushView(dialog, new ConfirmationDialogDelegate(), Ui.SLIDE_IMMEDIATE);
        return true;
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
            $.objectStoreErase("HISTORY");
            $.objectStoreErase("HISTORY_KEY");
            $.objectStoreErase("LAST_HISTORY_KEY");
            $.objectStoreErase("LAST_VIEWED_DATA");
            $.objectStoreErase("LAST_CHARGED_DATA");
        }
		return true;
    }
}
