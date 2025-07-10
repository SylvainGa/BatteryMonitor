using Toybox.WatchUi as Ui;
using Toybox.Application as App;

class NoGlanceView extends Ui.View {
    var mLaunched;

    function initialize() {
        View.initialize();
    }

    function onShow() {
        if (mLaunched == null) {
            mLaunched = true;

			var view = new BatteryMonitorView();
			Ui.pushView(view, new BatteryMonitorDelegate(view, view.method(:onReceive)), Ui.SLIDE_IMMEDIATE);
        }
        else {
            try {
                Ui.popView(Ui.SLIDE_IMMEDIATE); 
            }
            catch (e) {
                System.exit();
            }
        }
    }

    function onLayout(dc) {
        setLayout(Rez.Layouts.NoGlanceLayout(dc));
    }
}

class NoGlanceDelegate extends Ui.BehaviorDelegate {
    function initialize() {
        BehaviorDelegate.initialize();
    }
}