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

			var view = new BatteryMonitorView(false);
            var delegate = new BatteryMonitorDelegate(view, view.method(:onReceiveFromDelegate), false);

            App.getApp().mView = view;
            App.getApp().mDelegate = delegate;

            /*DEBUG*/ logMessage(("Launching main view"));
			Ui.pushView(view, delegate, Ui.SLIDE_IMMEDIATE);
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