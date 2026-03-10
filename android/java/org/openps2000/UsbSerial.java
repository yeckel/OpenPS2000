// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright © 2026 Libor Tomsik, OK1CHP
//
// UsbSerial.java — Android USB Host CDC-ACM serial port implementation.
// Called from C++ (AndroidSerialTransport) via QJniObject.
//
// EA-PS 2084-05 B presents as a USB CDC-ACM device (VID 0x0AAD).
// This class opens the USB device, sets line coding (115200/8/O/1),
// and provides synchronous read/write via bulk transfers.
//
package org.openps2000;

import android.content.Context;
import android.hardware.usb.UsbConstants;
import android.hardware.usb.UsbDevice;
import android.hardware.usb.UsbDeviceConnection;
import android.hardware.usb.UsbEndpoint;
import android.hardware.usb.UsbInterface;
import android.hardware.usb.UsbManager;
import android.util.Log;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;

public class UsbSerial {
    private static final String TAG = "UsbSerial";

    // EA Elektro-Automatik vendor ID
    private static final int EA_VID = 0x0AAD;

    // CDC-ACM control requests
    private static final int SET_LINE_CODING        = 0x20;
    private static final int SET_CONTROL_LINE_STATE = 0x22;
    private static final int REQUEST_TYPE_CLASS_INTERFACE = 0x21;

    // Line coding: 115200 baud, 1 stop bit, odd parity (1), 8 data bits
    private static final byte[] LINE_CODING_115200_ODD = {
        (byte)0x00, (byte)0xC2, (byte)0x01, (byte)0x00, // 115200 LE
        (byte)0x00,  // 1 stop bit
        (byte)0x01,  // odd parity
        (byte)0x08   // 8 data bits
    };

    private UsbManager         mUsbManager;
    private UsbDevice          mDevice;
    private UsbDeviceConnection mConnection;
    private UsbInterface       mDataInterface;
    private UsbEndpoint        mEndpointIn;
    private UsbEndpoint        mEndpointOut;
    private int                mControlInterface = -1;

    private static UsbSerial sInstance;

    // ── Singleton ─────────────────────────────────────────────────────────

    public static synchronized UsbSerial getInstance() {
        if (sInstance == null) sInstance = new UsbSerial();
        return sInstance;
    }

    private UsbSerial() {}

    // ── Device discovery ──────────────────────────────────────────────────

    /** Returns list of connected EA-PS device names for display in Settings UI. */
    public static String[] listDevices(Context ctx) {
        UsbManager mgr = (UsbManager) ctx.getSystemService(Context.USB_SERVICE);
        HashMap<String, UsbDevice> map = mgr.getDeviceList();
        List<String> names = new ArrayList<>();
        for (UsbDevice d : map.values()) {
            if (d.getVendorId() == EA_VID) {
                names.add(d.getDeviceName() + "|" + d.getProductName()
                        + " (VID=" + String.format("0x%04X", d.getVendorId())
                        + " PID=" + String.format("0x%04X", d.getProductId()) + ")");
            }
        }
        return names.toArray(new String[0]);
    }

    /** Find the first EA device; returns its device name or empty string. */
    public static String findEaDevice(Context ctx) {
        UsbManager mgr = (UsbManager) ctx.getSystemService(Context.USB_SERVICE);
        for (UsbDevice d : mgr.getDeviceList().values()) {
            if (d.getVendorId() == EA_VID) return d.getDeviceName();
        }
        return "";
    }

    // ── Open / Close ──────────────────────────────────────────────────────

    /**
     * Open a USB CDC-ACM serial port.
     * @param ctx     Android Context (activity or application context)
     * @param devName Device name from UsbManager (e.g. "/dev/bus/usb/001/002"),
     *                or empty to auto-select the first EA device.
     * @return true on success
     */
    public synchronized boolean open(Context ctx, String devName) {
        mUsbManager = (UsbManager) ctx.getSystemService(Context.USB_SERVICE);

        // Find device
        mDevice = null;
        for (UsbDevice d : mUsbManager.getDeviceList().values()) {
            if (devName.isEmpty()) {
                if (d.getVendorId() == EA_VID) { mDevice = d; break; }
            } else {
                if (d.getDeviceName().equals(devName)) { mDevice = d; break; }
            }
        }
        if (mDevice == null) {
            Log.e(TAG, "Device not found: " + devName);
            return false;
        }
        if (!mUsbManager.hasPermission(mDevice)) {
            Log.e(TAG, "No USB permission for " + mDevice.getDeviceName());
            return false;
        }

        mConnection = mUsbManager.openDevice(mDevice);
        if (mConnection == null) {
            Log.e(TAG, "Failed to open device");
            return false;
        }

        // Find CDC interfaces
        mDataInterface  = null;
        mEndpointIn     = null;
        mEndpointOut    = null;
        mControlInterface = -1;

        for (int i = 0; i < mDevice.getInterfaceCount(); i++) {
            UsbInterface intf = mDevice.getInterface(i);
            int cls = intf.getInterfaceClass();

            // CDC Communication Interface (class 2) — for control requests
            if (cls == UsbConstants.USB_CLASS_COMM && mControlInterface < 0) {
                mControlInterface = intf.getId();
                mConnection.claimInterface(intf, true);
            }
            // CDC Data Interface (class 10) — for bulk transfers
            if (cls == UsbConstants.USB_CLASS_CDC_DATA && mDataInterface == null) {
                mDataInterface = intf;
                mConnection.claimInterface(intf, true);
                for (int ep = 0; ep < intf.getEndpointCount(); ep++) {
                    UsbEndpoint e = intf.getEndpoint(ep);
                    if (e.getType() == UsbConstants.USB_ENDPOINT_XFER_BULK) {
                        if (e.getDirection() == UsbConstants.USB_DIR_IN)
                            mEndpointIn  = e;
                        else
                            mEndpointOut = e;
                    }
                }
            }
        }

        if (mDataInterface == null || mEndpointIn == null || mEndpointOut == null) {
            Log.e(TAG, "Could not find CDC-ACM data interface / endpoints");
            mConnection.close();
            mConnection = null;
            return false;
        }

        // Set line coding: 115200, odd parity, 8 bits, 1 stop bit
        int r = mConnection.controlTransfer(
                REQUEST_TYPE_CLASS_INTERFACE, SET_LINE_CODING,
                0, mControlInterface >= 0 ? mControlInterface : 0,
                LINE_CODING_115200_ODD, LINE_CODING_115200_ODD.length, 500);
        if (r < 0) Log.w(TAG, "SET_LINE_CODING failed (may still work): " + r);

        // Assert DTR + RTS (activate the line)
        r = mConnection.controlTransfer(
                REQUEST_TYPE_CLASS_INTERFACE, SET_CONTROL_LINE_STATE,
                0x03, mControlInterface >= 0 ? mControlInterface : 0,
                null, 0, 500);
        if (r < 0) Log.w(TAG, "SET_CONTROL_LINE_STATE failed (may still work): " + r);

        Log.i(TAG, "Opened " + mDevice.getDeviceName()
                + " [" + mDevice.getProductName() + "]");
        return true;
    }

    public synchronized void close() {
        if (mConnection != null) {
            if (mDataInterface  != null) mConnection.releaseInterface(mDataInterface);
            mConnection.close();
        }
        mConnection    = null;
        mDevice        = null;
        mDataInterface = null;
        mEndpointIn    = null;
        mEndpointOut   = null;
    }

    public synchronized boolean isOpen() {
        return mConnection != null && mEndpointIn != null;
    }

    // ── I/O ───────────────────────────────────────────────────────────────

    /**
     * Write bytes to the device. Returns number of bytes written, or -1 on error.
     * Timeout: 500 ms.
     */
    public synchronized int write(byte[] data) {
        if (!isOpen()) return -1;
        return mConnection.bulkTransfer(mEndpointOut, data, data.length, 500);
    }

    /**
     * Read up to maxLen bytes. Returns the number of bytes actually read,
     * 0 on timeout, -1 on error.
     * Timeout: 200 ms (must be shorter than the 250 ms poll interval).
     */
    public synchronized int read(byte[] buf, int maxLen) {
        if (!isOpen()) return -1;
        return mConnection.bulkTransfer(mEndpointIn, buf, maxLen, 200);
    }

    /** Request USB permission for the first detected EA device via system dialog. */
    public static void requestPermission(Context ctx,
            android.app.PendingIntent pi) {
        UsbManager mgr = (UsbManager) ctx.getSystemService(Context.USB_SERVICE);
        for (UsbDevice d : mgr.getDeviceList().values()) {
            if (d.getVendorId() == EA_VID) {
                mgr.requestPermission(d, pi);
                return;
            }
        }
    }

    // ── Static wrappers for JNI convenience ───────────────────────────────
    // These delegate to the singleton so C++ can call them as static methods.

    public static boolean open(Context ctx, String devName) {
        return getInstance().open(ctx, devName);
    }

    public static void close() {
        getInstance().close();
    }

    public static int write(byte[] data) {
        return getInstance().write(data);
    }

    public static int read(byte[] buf, int maxLen) {
        return getInstance().read(buf, maxLen);
    }
}
