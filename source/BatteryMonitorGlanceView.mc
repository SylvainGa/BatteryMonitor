using Toybox.System as Sys;
using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.Application as App;
using Toybox.Application.Storage;
using Toybox.Application.Properties;
using Toybox.Time;
using Toybox.Time.Gregorian;

(:glance, :can_glance)
class BatteryMonitorGlanceView extends Ui.GlanceView {
	var mHistoryClass; // Contains the current history as well as its helper functions
	var mRefreshTimer;
	var mRefreshCount;
	var mFontType;
    var mFontHeight;
	var mSummaryMode;
    var mProjectionType;
	var mHistoryLastPos;
    var mSlopeNeedsCalc;
    var mSlopeNeedsFirstCalc;
    var mNowData;
    var mPleaseWaitVisible;
    var mNewDataSize;

    //DEBUG*/ var mUpdateWholeStartTime;
	//DEBUG*/ var mUpdateStartTime;
	//DEBUG*/ var mFreeMemory;

    function initialize() {
        //DEBUG */ logMessage("Init1 Free memory " + (Sys.getSystemStats().freeMemory / 1024).toNumber() + " KB");
        GlanceView.initialize();
        //DEBUG */ logMessage("Init2 Free memory " + (Sys.getSystemStats().freeMemory / 1024).toNumber() + " KB");

        mHistoryClass = new HistoryClass();
        //DEBUG */ logMessage("Init3 Free memory " + (Sys.getSystemStats().freeMemory / 1024).toNumber() + " KB");

        onSettingsChanged(true);
        //DEBUG */ logMessage("Init4 Free memory " + (Sys.getSystemStats().freeMemory / 1024).toNumber() + " KB");
    }

    function onShow() {
    }

    function onHide() {
        if (mRefreshTimer) {
            mRefreshTimer.stop();
            mRefreshTimer = null;
        }
    }

	function onRefreshTimer() as Void {
		mRefreshCount++;
        mNewDataSize = $.objectStoreGet("RECEIVED_DATA_COUNT", 0);

        if (mHistoryClass != null && App.getApp().getGlanceLaunchMode() == LAUNCH_WHOLE) {
            if (mRefreshCount % 12 == 0) { // Every minute, read a new set of data
                var data = mHistoryClass.getData();
                //DEBUG*/ logMessage("onRefreshTimer Read data " + data);
                mHistoryClass.analyzeAndStoreData(data, 1, false);
            }
        }

        var stats = Sys.getSystemStats();
        var battery = (stats.battery * 10).toNumber(); // * 10 to keep one decimal place without using the space of a float variable
        var solar = (stats.solarIntensity == null ? null : stats.solarIntensity >= 0 ? stats.solarIntensity : 0);
        var now = Time.now().value(); //in seconds from UNIX epoch in UTC
        var nowData = [now, battery, solar];
        if (Sys.getSystemStats().charging) {
            var chargingData = $.objectStoreGet("STARTED_CHARGING_DATA", null);
            if (chargingData == null) {
                /*DEBUG*/ logMessage("onRefreshTimer: Started charging at " + nowData);
                $.objectStorePut("STARTED_CHARGING_DATA", nowData);
            }
            //DEBUG*/ logMessage("onRefreshTimer: Charging " + nowData);
            $.objectStorePut("LAST_CHARGE_DATA", nowData);
        }
        else {
            /*DEBUG*/ if ($.objectStoreGet("STARTED_CHARGING_DATA", null) != null) { logMessage("onRefreshTimer: Finished charging at " + nowData); }
            $.objectStoreErase("STARTED_CHARGING_DATA");
        }

		//DEBUG*/ logMessage("onRefreshTimer requestUpdate");
		Ui.requestUpdate();
    }

    function onLayout(dc) {
        //DEBUG */ logMessage("Layout1 Free memory " + (Sys.getSystemStats().freeMemory / 1024).toNumber() + " KB");
		var fonts = [Gfx.FONT_XTINY, Gfx.FONT_TINY, Gfx.FONT_SMALL, Gfx.FONT_MEDIUM, Gfx.FONT_LARGE];

        // FInd the right font to draw two lines on screen
		for (var i = fonts.size() - 1; i >= 0 ; i--) {
			var fontHeight = Gfx.getFontHeight(fonts[i]);
			if (dc.getHeight() / fontHeight == 2) {
				mFontType = fonts[i];
				break;
			}
		}

		if (mFontType == null) {
			mFontType = Gfx.FONT_LARGE;
		}

		mFontHeight = Gfx.getFontHeight(mFontType);
        mSlopeNeedsCalc = true;
        mSlopeNeedsFirstCalc = true;
        mPleaseWaitVisible = false;
        mNewDataSize = $.objectStoreGet("RECEIVED_DATA_COUNT", 0);

        //DEBUG */ logMessage("Layout2 Free memory " + (Sys.getSystemStats().freeMemory / 1024).toNumber() + " KB");
    }

    function onSettingsChanged(fromInit) {
        mSummaryMode = 0;
		try {
			mSummaryMode = Properties.getValue("SummaryMode");
		}
		catch (e) {
			mSummaryMode = 0;
		}

        mProjectionType = 0;
        try {
			mProjectionType = Properties.getValue("GlanceProjectionType");

        }
        catch (e) {
			mProjectionType = 0;
        }

        if (mHistoryClass != null) {
    		mHistoryClass.onSettingsChanged(fromInit);
        }
    }

    function onUpdate(dc) {
        var fgColor = Gfx.COLOR_WHITE;
        var bgColor = Gfx.COLOR_TRANSPARENT;

        // Clear the screen with a black background so devices like my Edge 840 (usually a white background during daytime) can actually show something
        if (App.getApp().getTheme() == THEME_LIGHT) {
            fgColor = Gfx.COLOR_BLACK;
            bgColor = Gfx.COLOR_TRANSPARENT;
        }

        dc.setColor(fgColor, bgColor);
        dc.clear();

        var battery = Sys.getSystemStats().battery;
        var colorBat;
        if (battery >= 20) {
            colorBat = COLOR_BAT_OK;
        }
        else if (battery >= 10) {
            colorBat = COLOR_BAT_LOW;
        }
        else {
            colorBat = COLOR_BAT_CRITICAL;
        }

        dc.setColor(colorBat, Graphics.COLOR_TRANSPARENT);
        var batteryStr = $.stripTrailingZeros(battery.format("%0.1f")) + (Sys.getSystemStats().charging ? "+%" : "%");

        var batteryStrLen = dc.getTextWidthInPixels(batteryStr + " ", mFontType);
        dc.drawText(0, 0, mFontType, batteryStr, Graphics.TEXT_JUSTIFY_LEFT);

        //DEBUG */ var freeMemory = (Sys.getSystemStats().freeMemory / 1024).toNumber(); if (mFreeMemory == null || mFreeMemory != freeMemory) { mFreeMemory = freeMemory; logMessage("Free memory " + freeMemory + " KB"); }
		//DEBUG*/ if (mUpdateWholeStartTime == null) { mUpdateWholeStartTime = Sys.getTimer(); }

        if (mHistoryClass != null && App.getApp().getGlanceLaunchMode() == LAUNCH_WHOLE) {
    		//DEBUG*/ logMessage("LAUNCH_WHOLE");
            // Draw the two/three rows of text on the glance widget
            if (mHistoryClass.getHistory() == null) {
                if (mPleaseWaitVisible == false) { // Somehow, the first requestUpdate doesn't show the Please Wait so I have to come back and reshow before reading the data
                    /*DEBUG*/ logMessage("LAUNCH_WHOLE");
                    /*DEBUG*/ logMessage("Free memory 1 " + (Sys.getSystemStats().freeMemory / 1024).toNumber() + " KB");
                    //DEBUG*/ mUpdateStartTime = Sys.getTimer();
                    //DEBUG*/ logMessage("Displaying first please wait");
                    mPleaseWaitVisible = true;
                    showPleaseWait(dc, fgColor);
                    Ui.requestUpdate(); // Needed so we can show a 'please wait' message whlle we're reading our data
                    return;
                }

                //DEBUG*/ var endTime = Sys.getTimer(); Sys.println("before getLatestHistoryFromStorage took " + (endTime - mUpdateStartTime) + " msec"); mUpdateStartTime = endTime;
                //DEBUG*/ logMessage("Getting latest history");
                showPleaseWait(dc, fgColor);
                mHistoryClass.getLatestHistoryFromStorage();
                /*DEBUG*/ logMessage("Free memory 2 " + (Sys.getSystemStats().freeMemory / 1024).toNumber() + " KB");
                Ui.requestUpdate(); // Time consuming, stop now and ask for another time slice
                return;
            }

            var receivedData = $.objectStoreGet("RECEIVED_DATA", []);
            if (receivedData.size() > 0 || mNowData == null) {
                /*DEBUG*/ logMessage("Free memory 3 " + (Sys.getSystemStats().freeMemory / 1024).toNumber() + " KB");
                //DEBUG*/ var endTime = Sys.getTimer(); if (mUpdateStartTime != null) { Sys.println("before reading background data took " + (endTime - mUpdateStartTime) + " msec"); } mUpdateStartTime = endTime;
                showPleaseWait(dc, fgColor);

                //DEBUG*/ if (receivedData.size() > 0) { logMessage("Processing background data"); }
                if (mNowData == null) {
                    //DEBUG*/ logMessage("tagging nowData to background data");
                    mNowData = mHistoryClass.getData();
                    receivedData.addAll(mNowData);
                }

                var added = mHistoryClass.analyzeAndStoreData(receivedData, receivedData.size() / 3, false);
                if (added > 1) {
                    //DEBUG*/ logMessage("Saving history");
    				mHistoryClass.storeHistory(true);
                }

                receivedData = null; // We don't need it anymore, reclaim its space
    			$.objectStoreErase("RECEIVED_DATA"); // Now that we've processed it, get rid of that data
    			$.objectStorePut("RECEIVED_DATA_COUNT", 0); // Clear that too so we don't write in dark red when above HISTORY_MAX

                /*DEBUG*/ logMessage("Free memory 4 " + (Sys.getSystemStats().freeMemory / 1024).toNumber() + " KB");

                if (added > 0 && mHistoryClass.getHistoryNeedsReload() == true) {
                    Ui.requestUpdate(); // Could be time consuming, stop now and ask for another time slice
                    return;
                }
            }

            if (mSlopeNeedsFirstCalc == true) {
                //DEBUG*/ var endTime = Sys.getTimer(); Sys.println("before slopes took " + (endTime - mUpdateStartTime) + " msec"); mUpdateStartTime = endTime;
                //DEBUG*/ logMessage("Doing initial calc of slopes");

                showPleaseWait(dc, fgColor);

                mHistoryClass.initDownSlope();
                mSlopeNeedsFirstCalc = false;

                /*DEBUG*/ logMessage("Free memory 5 " + (Sys.getSystemStats().freeMemory / 1024).toNumber() + " KB");

                Ui.requestUpdate(); // Could be time consuming, stop now and ask for another time slice
                return;
            }

            if (mRefreshTimer == null) {
                //DEBUG*/ var endTime = Sys.getTimer(); Sys.println("before refresh timer took " + (endTime - mUpdateStartTime) + " msec"); mUpdateStartTime = endTime;
                //DEBUG*/ logMessage("Starting refresh timer");
                mRefreshCount = 0;
                mRefreshTimer = new Timer.Timer();
                mRefreshTimer.start(method(:onRefreshTimer), 5000, true); // Check every five second
            }
            //DEBUG*/ else { mUpdateStartTime = null; }

		//DEBUG*/ if (mUpdateStartTime != null) { var endTime = Sys.getTimer(); Sys.println("after timer took " + (endTime - mUpdateStartTime) + " msec"); Sys.println("**DONE** Took " + (endTime - mUpdateWholeStartTime) + " msec"); }
        }

		mPleaseWaitVisible = false; // We don't need our 'Please Wait' popup anymore

        var remainingStr = Ui.loadResource(Rez.Strings.NotAvailableShort);
        var dischargeStr = Ui.loadResource(Rez.Strings.NotAvailableShort);
        var remainingStrLen = 0;

        if (mProjectionType == 0) {
            if (Sys.getSystemStats().charging == false) { // There won't be a since last charge if we're charging...
                var lastChargeData = $.objectStoreGet("LAST_CHARGE_DATA", null);
                if (lastChargeData != null ) {
                    var now = Time.now().value(); //in seconds from UNIX epoch in UTC
                    var timeDiff = now - lastChargeData[TIMESTAMP];
                    if (timeDiff != 0) { // Sanity check
                        var batAtLastCharge = $.stripMarkers(lastChargeData[BATTERY]) /  10.0;

                        if (batAtLastCharge > battery) { // Sanity check
                            var batDiff = batAtLastCharge - battery;
                            var dischargePerMin = batDiff * 60.0 / timeDiff;
                            remainingStr = $.minToStr(battery / dischargePerMin, false);
                            remainingStrLen = dc.getTextWidthInPixels(remainingStr + " ", mFontType);

                            var downSlopeHours = dischargePerMin * 60;
                            if ((downSlopeHours * 24 <= 100 && mSummaryMode == 0) || mSummaryMode == 2) {
                                dischargeStr = $.stripTrailingZeros((downSlopeHours * 24).format("%0.1f")) + Ui.loadResource(Rez.Strings.PercentPerDay);
                            }
                            else {
                                dischargeStr = $.stripTrailingZeros((downSlopeHours).format("%0.2f")) + Ui.loadResource(Rez.Strings.PercentPerHour);
                            }

                            //DEBUG*/ var lastChargeMoment = new Time.Moment(lastChargeData[0]); var lastChargeInfo = Gregorian.info(lastChargeMoment, Time.FORMAT_MEDIUM); logMessage("Last charge: " + lastChargeInfo.hour + "h" + lastChargeInfo.min.format("%02d") + "m" + lastChargeInfo.sec.format("%02d") + "s, " + secToStr(timeDiff) + " ago (" + timeDiff + " sec). Battery was " + batAtLastCharge.format("%0.1f") + "%. Now at " + battery.format("%0.1f") + "%. Discharge at " + dischargeStr + ". Remaining is " + remainingStr);
                        }
                        //DEBUG*/ else { logMessage("Glance:batAtLastCharge was " + batAtLastCharge + " and battery is " + battery); }
                    }
                    //DEBUG*/ else { logMessage("Glance:Time diff is 0"); }
                }
                //DEBUG*/ else { logMessage("Glance:No last charge data"); }
            }
            //DEBUG*/ else { logMessage("Glance:Watch is charging"); }
        }
        else { // Use long term projection
            // See if we can use our previously calculated slope data
            var downSlopeData = $.objectStoreGet("LAST_SLOPE_DATA", null);
            var downSlopeSec;
            if (downSlopeData != null) {
                downSlopeSec = downSlopeData[0];
                mHistoryLastPos = downSlopeData[1];
            }

            if (mHistoryClass != null && App.getApp().getGlanceLaunchMode() == LAUNCH_WHOLE && (downSlopeSec == null || mSlopeNeedsCalc == true || mHistoryLastPos != mHistoryClass.getHistorySize())) { // ONLY do if we read mHistory (ie, LAUNCH_WHOLE) 
                // Calculate projected usage slope
                var downSlopeResult = mHistoryClass.downSlope(false);
                downSlopeSec = downSlopeResult[0];
                mSlopeNeedsCalc = downSlopeResult[1];
                mHistoryLastPos = mHistoryClass.getHistorySize();
                downSlopeData = [downSlopeSec, mHistoryLastPos];
                $.objectStorePut("LAST_SLOPE_DATA", downSlopeData);
            }

            if (downSlopeSec != null) {
                var downSlopeMin = downSlopeSec * 60;
                remainingStr = $.minToStr(battery / downSlopeMin, false);
                remainingStrLen = dc.getTextWidthInPixels(remainingStr + " ", mFontType);

                var downSlopeHours = downSlopeSec * 60 * 60;
                if ((downSlopeHours * 24 <= 100 && mSummaryMode == 0) || mSummaryMode == 2) {
                    dischargeStr = $.stripTrailingZeros((downSlopeHours * 24).format("%0.1f")) + Ui.loadResource(Rez.Strings.PercentPerDay);
                }
                else {
                    dischargeStr = $.stripTrailingZeros((downSlopeHours).format("%0.2f")) + Ui.loadResource(Rez.Strings.PercentPerHour);
                }	
            }
            else if (mHistoryClass == null || App.getApp().getGlanceLaunchMode() == LAUNCH_FAST) { //If one of these are true, we need to launch the app to get the first value
                remainingStr = Ui.loadResource(Rez.Strings.LaunchApp);
                dischargeStr = "";
            }
        }

        var warningColor = fgColor;
        var topCount = mNewDataSize / 10000;
        if (topCount > HISTORY_MAX) { // If our data waiting to be processed is above the HISTORY_MAX size, flag it red (it had lost resolution)
            warningColor = Gfx.COLOR_RED;
        }
        else if (topCount > HISTORY_MAX * 3 / 5) { // If our data waiting to be processed is above 60% of the HISTORY_MAX size, flag it yellow (warning, about to loose resolution)
            warningColor = Gfx.COLOR_YELLOW;
        }

        dc.setColor(fgColor, Gfx.COLOR_TRANSPARENT);
        dc.drawText(0, mFontHeight, mFontType, remainingStr, Gfx.TEXT_JUSTIFY_LEFT);
        var xPos = (batteryStrLen > remainingStrLen ? batteryStrLen : remainingStrLen);
        dc.setColor(warningColor, Gfx.COLOR_TRANSPARENT);
        var yPos = mFontHeight / 2;
        /*DEBUG*/ dc.drawText(xPos, 0, mFontType, topCount + "/" + (mNewDataSize - topCount * 10000), Gfx.TEXT_JUSTIFY_LEFT); yPos = mFontHeight;
        dc.drawText(xPos, yPos, mFontType, dischargeStr, Gfx.TEXT_JUSTIFY_LEFT);
    }

	function showPleaseWait(dc, fgColor) {
        if (mPleaseWaitVisible == true) {
            dc.setColor(fgColor, Gfx.COLOR_TRANSPARENT);
            dc.drawText(0, mFontHeight, mFontType, Ui.loadResource(Rez.Strings.PleaseWait), Gfx.TEXT_JUSTIFY_LEFT);
        }
    }
}
