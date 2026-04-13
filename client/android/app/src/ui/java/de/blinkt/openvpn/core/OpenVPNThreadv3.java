/*
 * Temporary OVPN3 stub for environments without SWIG-generated bindings.
 * Keeps project buildable while using ovpn2 runtime path.
 */
package de.blinkt.openvpn.core;

import de.blinkt.openvpn.VpnProfile;
import com.ruoxue.vpn.R;

public class OpenVPNThreadv3 implements Runnable, OpenVPNManagement {
    private final OpenVPNService mService;
    private final VpnProfile mProfile;
    private volatile boolean mRunning;

    public OpenVPNThreadv3(OpenVPNService openVpnService, VpnProfile vp) {
        mService = openVpnService;
        mProfile = vp;
    }

    @Override
    public void run() {
        mRunning = true;
        VpnStatus.logError("OpenVPN3 runtime is disabled (SWIG bindings missing).");
        if (mProfile != null) {
            VpnStatus.updateStateString(
                    "NOPROCESS",
                    "OpenVPN3 unavailable for profile " + mProfile.mName,
                    R.string.state_noprocess,
                    ConnectionStatus.LEVEL_NOTCONNECTED
            );
        }
        mRunning = false;
    }

    @Override
    public void reconnect() {
        VpnStatus.logError("OpenVPN3 reconnect ignored (runtime unavailable).");
    }

    @Override
    public void pause(pauseReason reason) {
        VpnStatus.logInfo("OpenVPN3 pause ignored: " + reason);
    }

    @Override
    public void resume() {
        VpnStatus.logInfo("OpenVPN3 resume ignored.");
    }

    @Override
    public boolean stopVPN(boolean replaceConnection) {
        mRunning = false;
        return false;
    }

    @Override
    public void networkChange(boolean sameNetwork) {
        VpnStatus.logInfo("OpenVPN3 networkChange ignored.");
    }

    @Override
    public void setPauseCallback(PausedStateCallback callback) {
        // no-op
    }

    @Override
    public void sendCRResponse(String response) {
        VpnStatus.logInfo("OpenVPN3 CR response ignored.");
    }
}
