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

    function initialize() {
        GlanceView.initialize();
    }

    function onShow() {
        onSettingsChanged();

		mIsSolar = Sys.getSystemStats().solarIntensity != null ? true : false;
		mElementSize = mIsSolar ? HISTORY_ELEMENT_SIZE_SOLAR : HISTORY_ELEMENT_SIZE;

		mRefreshCount = 0;
		mTimer = new Timer.Timer();
		mTimer.start(method(:refreshTimer), 5000, true); // Check every five second
    }

    function onHide() {
        if (mTimer) {
            mTimer.stop();
            mTimer = null;
        }
    }

	function refreshTimer() as Void {
		mRefreshCount++;
		if (mRefreshCount == 12) { // Every minute, read a new set of data
            var data = $.getData();
			//DEBUG*/ logMessage("refreshTimer Read data " + data);
			$.analyzeAndStoreData([data], 1, false);
			mRefreshCount = 0;
		}

        if (Sys.getSystemStats().charging) {
            var stats = Sys.getSystemStats();
            var battery = (stats.battery * 10).toNumber(); // * 10 to keep one decimal place without using the space of a float variable
            var solar = (stats.solarIntensity == null ? null : stats.solarIntensity >= 0 ? stats.solarIntensity : 0);
            var now = Time.now().value(); //in seconds from UNIX epoch in UTC

            var chargingData = $.objectStoreGet("STARTED_CHARGING_DATA", null);
            if (chargingData == null) {
                $.objectStorePut("STARTED_CHARGING_DATA", [now, battery, solar]);
            }
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
        mSlopeNeedsCalc = false;
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
        // Draw the two/three rows of text on the glance widget

        // Testing array passing by references
        // var appArray = App.getApp().mArray;
        // var appArraySize = App.getApp().mArraySize;
		// Sys.println("onUpdate App array is " + appArray + " size is " + appArraySize);

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
        var batteryStr = battery.toNumber() + (Sys.getSystemStats().charging ? "+%" : "%");

        var batteryStrLen = dc.getTextWidthInPixels(batteryStr + " ", mFontType);
        dc.drawText(0, 0, mFontType, batteryStr, Graphics.TEXT_JUSTIFY_LEFT);

        var remainingStr = Ui.loadResource(Rez.Strings.NotAvailableShort);
        var dischargeStr = Ui.loadResource(Rez.Strings.NotAvailableShort);
        var remainingStrLen = 0;

        if (mProjectionType == 0) {
            if (Sys.getSystemStats().charging == false) { // There won't be a since last charge if we're charging...
                var lastChargeData = LastChargeData();
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
                                dischargeStr = (downSlopeHours * 24).format("%0.1f") + Ui.loadResource(Rez.Strings.PercentPerDay);
                            }
                            else {
                                dischargeStr = (downSlopeHours).format("%0.2f") + Ui.loadResource(Rez.Strings.PercentPerHour);
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
                mHistoryLastPos = downSlopeData[1]; // We don't need to bother with downSlopeData[2] here as it's not used
            }
            if (downSlopeSec == null || mSlopeNeedsCalc == true || mHistoryLastPos != App.getApp().mHistorySize) {
                // Calculate projected usage slope
                var downSlopeResult = $.downSlope();
                downSlopeSec = downSlopeResult[0];
                mSlopeNeedsCalc = downSlopeResult[1];
                var slopesSize = downSlopeResult[2];
                mHistoryLastPos = App.getApp().mHistorySize;
                downSlopeData = [downSlopeSec, mHistoryLastPos, slopesSize];
                $.objectStorePut("LAST_SLOPE_DATA", downSlopeData);
            }

            if (downSlopeSec != null) {
                var downSlopeMin = downSlopeSec * 60;
                remainingStr = $.minToStr(battery / downSlopeMin, false);
                remainingStrLen = dc.getTextWidthInPixels(remainingStr + " ", mFontType);

                var downSlopeHours = downSlopeSec * 60 * 60;
                if ((downSlopeHours * 24 <= 100 && mSummaryMode == 0) || mSummaryMode == 2) {
                    dischargeStr = (downSlopeHours * 24).format("%0.1f") + Ui.loadResource(Rez.Strings.PercentPerDay);
                }
                else {
                    dischargeStr = (downSlopeHours).format("%0.2f") + Ui.loadResource(Rez.Strings.PercentPerHour);
                }	
            } 
        }

        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(0, mFontHeight, mFontType, remainingStr, Gfx.TEXT_JUSTIFY_LEFT);
        var xPos = (batteryStrLen > remainingStrLen ? batteryStrLen : remainingStrLen);
        dc.drawText(xPos, mFontHeight / 2, mFontType, dischargeStr, Gfx.TEXT_JUSTIFY_LEFT);
    }

    function LastChargeData() {
        var history = App.getApp().mHistory;
        var historySize = App.getApp().getHistorySize();

		if (history != null) {
    		var bat2 = 0;
			for (var i = historySize - 1; i >= 0; i--) {
				var bat1 = $.stripMarkers(history[i * mElementSize + BATTERY]);
				if (bat2 > bat1) {
					i++; // We won't overflow as the first pass is always false with bat2 being 0
					var lastCharge = [history[i * mElementSize + TIMESTAMP], bat2, mIsSolar ? history[i * mElementSize + SOLAR] : null];
					$.objectStorePut("LAST_CHARGE_DATA", lastCharge);
					return lastCharge;
				}

				bat2 = bat1;
			}
		}

		var lastChargeData = $.objectStoreGet("LAST_CHARGE_DATA", null); // If we can't find the battery going up in the current history file, try to get it from the last time we saved the last charge (either here or in the main view)
    	return lastChargeData;
    }
    

}
