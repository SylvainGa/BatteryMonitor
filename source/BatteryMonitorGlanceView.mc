using Toybox.System as Sys;
using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.Application as App;
using Toybox.Application.Storage;
using Toybox.Application.Properties;
using Toybox.Time;
using Toybox.Time.Gregorian;

(:glance)
class BatteryMonitorGlanceView extends Ui.GlanceView {
	var mTimer;
	var mRefreshCount;
	var mFontType;
    var mFontHeight;
	var mSummaryMode;
	var mHistoryLastPos;

    function initialize() {
        GlanceView.initialize();
    }

    function onShow() {
        onSettingsChanged();

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
			/*DEBUG*/ logMessage("refreshTimer Read data " + data);
			$.analyzeAndStoreData([data], 1);
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

        // Testing array passing by references
        // var appArray = App.getApp().mArray;
        // var appArraySize = App.getApp().mArraySize;
		// Sys.println("onLayout App array is " + appArray + " size is " + appArraySize);
        // var myArray = [1, 2];
        // var ret = App.getApp().setArray(myArray);
        // appArray = ret[0];
        // appArraySize = ret[1];
		// Sys.println("onLayout App array is " + appArray + " and size " + appArraySize);
        // appArray.add(3);
        // appArraySize = App.getApp().getArraySize();
		// Sys.println("onLayout App array is " + appArray + " and size " + appArraySize);

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
    }

    function onSettingsChanged() {
		try {
			mSummaryMode = Properties.getValue("SummaryMode");
		}
		catch (e) {
			mSummaryMode = 0;
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

		var downSlopeSec = objectStoreGet("LAST_SLOPE_VALUE", null);
		if (downSlopeSec == null || mHistoryLastPos == null || mHistoryLastPos != App.getApp().mHistorySize) {
			downSlopeSec = $.downSlope();
			mHistoryLastPos = App.getApp().mHistorySize;
		}

        if (downSlopeSec != null) {
            dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
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

        dc.drawText(0, mFontHeight, mFontType, remainingStr, Gfx.TEXT_JUSTIFY_LEFT);

        var xPos = (batteryStrLen > remainingStrLen ? batteryStrLen : remainingStrLen);
        dc.drawText(xPos, mFontHeight / 2, mFontType, dischargeStr, Gfx.TEXT_JUSTIFY_LEFT);
    }
}
