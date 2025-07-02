using Toybox.System as Sys;
using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.Application.Storage;
using Toybox.Application.Properties;
using Toybox.Time;
using Toybox.Time.Gregorian;

(:glance)
class BatteryMonitorGlanceView extends Ui.GlanceView {
	var mFontType;
    var mFontHeight;
	var mSummaryMode;

    function initialize() {
        GlanceView.initialize();
    }

    function onShow() {
        onSettingsChanged();
    }

    function onHide() {
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
        var batteryStr = battery.toNumber() + "%" + (Sys.getSystemStats().charging ? "+" : "");

        var batteryStrLen = dc.getTextWidthInPixels(batteryStr + " ", mFontType);
        dc.drawText(0, 0, mFontType, batteryStr, Graphics.TEXT_JUSTIFY_LEFT);

        var remainingStr = Ui.loadResource(Rez.Strings.NotAvailableShort);
        var dischargeStr = Ui.loadResource(Rez.Strings.NotAvailableShort);
        var remainingStrLen = 0;
        var chartData = objectStoreGet("HISTORY_KEY", null);
        if ((chartData instanceof Toybox.Lang.Array)) {
        	chartData = chartData.reverse();

    		var downSlopeSec = downSlope(chartData);
		    if (downSlopeSec != null) {
				dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
                var downSlopeMin = downSlopeSec * 60;
                remainingStr = minToStr(battery / downSlopeMin, false);
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
        dc.drawText(0, mFontHeight, mFontType, remainingStr, Gfx.TEXT_JUSTIFY_LEFT);

        var xPos = (batteryStrLen > remainingStrLen ? batteryStrLen : remainingStrLen);
        dc.drawText(xPos, mFontHeight / 2, mFontType, dischargeStr, Gfx.TEXT_JUSTIFY_LEFT);
    }
}
