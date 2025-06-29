using Toybox.System as Sys;
using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.Application.Storage;
using Toybox.Application.Properties;
using Toybox.Time;
using Toybox.Time.Gregorian;

(:glance)
class BatteryMonitorGlanceView extends Ui.GlanceView {
    var mFontHeight;

    function initialize() {
        GlanceView.initialize();
    }

    function onShow() {
    }

    function onHide() {
    }

    function onLayout(dc) {
		mFontHeight = Graphics.getFontHeight(Gfx.FONT_TINY);
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
        var batteryStr = battery.toNumber() + "%";
        var batteryStrLen = dc.getTextWidthInPixels(batteryStr + " ", Graphics.FONT_TINY);
        dc.drawText(0, 0, Graphics.FONT_TINY, batteryStr, Graphics.TEXT_JUSTIFY_LEFT);

        var remainingStr = "N/A";
        var dischargeStr = "N/A";
        var remainingStrLen = 0;
        var chartData = objectStoreGet("HISTORY_KEY", null);
        if ((chartData instanceof Toybox.Lang.Array)) {
        	chartData = chartData.reverse();

    		var downSlopeSec = downSlope(chartData);
		    if (downSlopeSec != null) {
				dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
                var downSlopeMin = downSlopeSec * 60;
                remainingStr = minToStr(battery / downSlopeMin);
                remainingStrLen = dc.getTextWidthInPixels(remainingStr + " ", Graphics.FONT_TINY);

                var downSlopeHours = downSlopeSec * 60 * 60;
                if (downSlopeHours * 24 <= 100){
                    dischargeStr = (downSlopeHours * 24).toNumber() + "%/d";
                }
                else {
                    dischargeStr = (downSlopeHours).toNumber() + "%/h";
                }	
            }            
        }
        dc.drawText(0, mFontHeight, Gfx.FONT_TINY, remainingStr, Gfx.TEXT_JUSTIFY_LEFT);

        var xPos = (batteryStrLen > remainingStrLen ? batteryStrLen : remainingStrLen);
        dc.drawText(xPos, mFontHeight / 2, Gfx.FONT_TINY, dischargeStr, Gfx.TEXT_JUSTIFY_LEFT);
    }
}
