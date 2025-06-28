using Toybox.System as Sys;
using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.Application.Storage;
using Toybox.Application.Properties;
using Toybox.Time;
using Toybox.Time.Gregorian;

(:glance)
class BatteryMonitorGlanceView extends Ui.GlanceView {
    function initialize() {
        GlanceView.initialize();
    }

    function onShow() {
    }

    function onHide() {
    }

    function onLayout(dc) {
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

        dc.drawText(
            0,
            0,
            Graphics.FONT_TINY,
            "Battery Monitor\nCharge: " + battery.toNumber() + "%",
            Graphics.TEXT_JUSTIFY_LEFT
        );
    }
}
