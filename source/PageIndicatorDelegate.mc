//
// Copyright 2015-2023 by Garmin Ltd. or its subsidiaries.
// Subject to Garmin SDK License Agreement and Wearables
// Application Developer Agreement.
//

import Toybox.Lang;
import Toybox.WatchUi;

//! ViewLoop Delegate for handling the main primate views
//! and indicates the current page
class PageIndicatorDelegate extends WatchUi.ViewLoopDelegate {

    private var mViewLoop as ViewLoop;

    //! Constructor
    //! @param viewLoop The ViewLoop Object
    function initialize(viewLoop as ViewLoop) {
        ViewLoopDelegate.initialize(viewLoop);
        mViewLoop = viewLoop;
    }

    //! Handle going to the next view
    //! @return true if handled, false otherwise
    function onNextView() {
        mViewLoop.changeView(WatchUi.ViewLoop.DIRECTION_PREVIOUS);
        return true;
    }

    //! Handle going to the previous view
    //! @return true if handled, false otherwise
    function onPreviousView() {
        mViewLoop.changeView(WatchUi.ViewLoop.DIRECTION_NEXT);
        return true;
    }
}