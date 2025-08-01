//
// Copyright 2015-2023 by Garmin Ltd. or its subsidiaries.
// Subject to Garmin SDK License Agreement and Wearables
// Application Developer Agreement.
//

using Toybox.Application as App;
import Toybox.Lang;
import Toybox.WatchUi;

//! ViewLoop Factory which manages the main view/delegate paires
(:can_viewloop)
class PageIndicatorFactory extends WatchUi.ViewLoopFactory {
    var mView;
    var mDelegate;

    function initialize() {
        ViewLoopFactory.initialize();

        mView = new BatteryMonitorView(true);
        mDelegate = new BatteryMonitorDelegate(mView, mView.method(:onReceive), true);

        var app = App.getApp();
        app.mView = mView;
        app.mDelegate = mDelegate;
    }

    //! Retrieve a view/delegate pair for the page at the given index
    function getView(page as Number) as [ViewLoopFactory.Views] or [ViewLoopFactory.Views, ViewLoopFactory.Delegates] {
        mView.resetViewVariables();
        mView.setPage((App.getApp().mView.getPanelSize() - 1) - page);
        return [mView, mDelegate];
    }

    //! Return the number of view/delegate pairs that are managed by this factory
    function getSize() {
        return mView.getPanelSize();
    }
}

(:cant_viewloop)
class PageIndicatorFactory extends WatchUi.ViewLoopFactory {
}
