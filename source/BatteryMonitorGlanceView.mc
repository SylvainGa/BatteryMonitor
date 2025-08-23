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
    var mApp;
	var mTimer;
	var mRefreshCount;
	var mFontType;
    var mFontHeight;
	var mIsSolar;
	var mElementSize;
	var mSummaryMode;
    var mProjectionType;
	var mHistoryLastPos;
    var mSlopeNeedsCalc;
    var mSlopeNeedsFirstCalc;
    var mNowData;
    var mPleaseWaitVisible;
	//DEBUG*/ var mUpdateStartTime;

    function initialize() {
        GlanceView.initialize();
    }

    function onShow() {
        onSettingsChanged();

		mIsSolar = Sys.getSystemStats().solarIntensity != null ? true : false;
		mElementSize = mIsSolar ? HISTORY_ELEMENT_SIZE_SOLAR : HISTORY_ELEMENT_SIZE;

		mRefreshCount = 0;
		mTimer = new Timer.Timer();
		mTimer.start(method(:onRefreshTimer), 5000, true); // Check every five second
    }

    function onHide() {
        if (mTimer) {
            mTimer.stop();
            mTimer = null;
        }
    }

	function onRefreshTimer() as Void {
		mRefreshCount++;
        
        if (mApp.getGlanceLaunchMode() == LAUNCH_WHOLE) {
            if (mRefreshCount % 12 == 0) { // Every minute, read a new set of data
                var data = $.getData();
                //DEBUG*/ logMessage("onRefreshTimer Read data " + data);
                $.analyzeAndStoreData([data], 1, false);
            }
        }

        if (Sys.getSystemStats().charging) {
            var stats = Sys.getSystemStats();
            var battery = (stats.battery * 10).toNumber(); // * 10 to keep one decimal place without using the space of a float variable
            var solar = (stats.solarIntensity == null ? null : stats.solarIntensity >= 0 ? stats.solarIntensity : 0);
            var now = Time.now().value(); //in seconds from UNIX epoch in UTC
            var nowData = [now, battery, solar];

            var chargingData = $.objectStoreGet("STARTED_CHARGING_DATA", null);
            if (chargingData == null) {
                $.objectStorePut("STARTED_CHARGING_DATA", nowData);
            }
            //DEBUG*/ logMessage("onRefreshTimer: Charging " + nowData);
            $.objectStorePut("LAST_CHARGE_DATA", nowData);
        }
        else {
            $.objectStoreErase("STARTED_CHARGING_DATA");
        }

		Ui.requestUpdate();
    }

    function onLayout(dc) {
		var fonts = [Gfx.FONT_XTINY, Gfx.FONT_TINY, Gfx.FONT_SMALL, Gfx.FONT_MEDIUM, Gfx.FONT_LARGE];

		// The right font is about 10% of the screen size
		for (var i = 0; i < fonts.size(); i++) {
			var fontHeight = Gfx.getFontHeight(fonts[i]);
			if (dc.getHeight() / fontHeight < 3) {
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

        mApp = App.getApp();
    }

    function onSettingsChanged() {
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
    }

    function onUpdate(dc) {
        var fgColor = Gfx.COLOR_WHITE;
        var bgColor = Gfx.COLOR_TRANSPARENT;

        // Clear the screen with a black background so devices like my Edge 840 (usually a white background during daytime) can actually show something
        if (mApp.getTheme() == THEME_LIGHT) {
            fgColor = Gfx.COLOR_BLACK;
            bgColor = Gfx.COLOR_TRANSPARENT;
        }

        dc.setColor(fgColor, bgColor);
        dc.clear();

        //DEBUG */ logMessage("Free memory " + (Sys.getSystemStats().freeMemory / 1000).toNumber() + " KB");

        if (mApp.getGlanceLaunchMode() == LAUNCH_WHOLE) {
            // Draw the two/three rows of text on the glance widget
            if (mApp.mHistory == null) {
                if (mPleaseWaitVisible == false) { // Somehow, the first requestUpdate doesn't show the Please Wait so I have to come back and reshow before reading the data
                    //DEBUG*/ mUpdateStartTime = Sys.getTimer();
                    //DEBUG*/ logMessage("onUpdate: Displaying first please wait");
                    mPleaseWaitVisible = true;
                    showPleaseWait(dc, fgColor);
                    Ui.requestUpdate(); // Needed so we can show a 'please wait' message whlle we're reading our data
                    return;
                }

                //DEBUG*/ var endTime = Sys.getTimer(); Sys.println("onUpdate before getLatestHistoryFromStorage took " + (endTime - mUpdateStartTime) + " msec"); mUpdateStartTime = endTime;
                //DEBUG*/ logMessage("onUpdate: Getting latest history");
                showPleaseWait(dc, fgColor);
                mApp.getLatestHistoryFromStorage();
                Ui.requestUpdate(); // Time consuming, stop now and ask for another time slice
                return;
            }

            var receivedData = $.objectStoreGet("RECEIVED_DATA", []);
            if (receivedData.size() > 0 || mNowData == null) {
                //DEBUG*/ var endTime = Sys.getTimer(); Sys.println("onUpdate before reading background data took " + (endTime - mUpdateStartTime) + " msec"); mUpdateStartTime = endTime;
                showPleaseWait(dc, fgColor);

                $.objectStoreErase("RECEIVED_DATA"); // We'll process it, no need to keep its storage

                //DEBUG*/ if (receivedData.size() > 0) { logMessage("onUpdate: Processing background data"); }
                if (mNowData == null) {
                    //DEBUG*/ logMessage("onUpdate: tagging nowData to background data");
                    mNowData = $.getData();
                    receivedData.add(mNowData);
                }

                var added = $.analyzeAndStoreData(receivedData, receivedData.size(), false);
                if (added > 1) {
                    //DEBUG*/ logMessage("Saving history");
                    $.objectStorePut("HISTORY_" + mApp.mHistory[0 + TIMESTAMP], mApp.mHistory);
                    mApp.setHistoryModified(false);
                }
                if (added > 0 && mApp.getHistoryNeedsReload() == true) {
                    Ui.requestUpdate(); // Could be time consuming, stop now and ask for another time slice
                    return;
                }
            }

            if (mSlopeNeedsFirstCalc == true) {
                //DEBUG*/ var endTime = Sys.getTimer(); Sys.println("onUpdate before slopes took " + (endTime - mUpdateStartTime) + " msec"); mUpdateStartTime = endTime;
                //DEBUG*/ logMessage("onUpdate: Doing initial calc of slopes");

                showPleaseWait(dc, fgColor);

                $.initDownSlope();
                mSlopeNeedsFirstCalc = false;

                Ui.requestUpdate(); // Could be time consuming, stop now and ask for another time slice
                return;
            }

    		//DEBUG*/ var endTime = Sys.getTimer(); Sys.println("onUpdate after everything took " + (endTime - mUpdateStartTime) + " msec"); mUpdateStartTime = endTime;
        }

		mPleaseWaitVisible = false; // We don't need our 'Please Wait' popup anymore

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

            if (mApp.getGlanceLaunchMode == LAUNCH_WHOLE && (downSlopeSec == null || mSlopeNeedsCalc == true || mHistoryLastPos != mApp.mHistorySize)) { // ONLY do if we read mHistory (ie, LAUNCH_WHOLE) 
                // Calculate projected usage slope
                var downSlopeResult = $.downSlope(false);
                downSlopeSec = downSlopeResult[0];
                mSlopeNeedsCalc = downSlopeResult[1];
                mHistoryLastPos = mApp.mHistorySize;
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
        }

        dc.setColor(fgColor, Gfx.COLOR_TRANSPARENT);
        dc.drawText(0, mFontHeight, mFontType, remainingStr, Gfx.TEXT_JUSTIFY_LEFT);
        var xPos = (batteryStrLen > remainingStrLen ? batteryStrLen : remainingStrLen);
        dc.drawText(xPos, mFontHeight / 2, mFontType, dischargeStr, Gfx.TEXT_JUSTIFY_LEFT);
    }

	function showPleaseWait(dc, fgColor) {
        if (mPleaseWaitVisible == true) {
            dc.setColor(fgColor, Gfx.COLOR_TRANSPARENT);
            dc.drawText(0, dc.getHeight() / 2, mFontType, Ui.loadResource(Rez.Strings.PleaseWait), Gfx.TEXT_JUSTIFY_LEFT | Gfx.TEXT_JUSTIFY_VCENTER);
        }
    }
}
