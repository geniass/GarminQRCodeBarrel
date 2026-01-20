import Toybox.Lang;
import Toybox.WatchUi;

// Input delegate for standalone app
// Handles button presses and back navigation
class QRAppDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    // Handle back button - exit app
    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }
}
