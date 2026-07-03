<#
.SYNOPSIS
Compile the DPAPI-NG P/Invoke type used by the DpapiNG secrets provider (internal).

.DESCRIPTION
Internal helper for the IDBridge secret vault. Adds the [IDBridge.DpapiNG] type, a thin
P/Invoke wrapper over ncrypt.dll (NCryptCreateProtectionDescriptor / NCryptProtectSecret /
NCryptUnprotectSecret) so secrets can be protected to an AD principal (e.g. a gMSA SID)
with no external module. The type is compiled once per session; later calls are no-ops.

.EXAMPLE
Import-IDBridgeDpapiNGType
$blob = [IDBridge.DpapiNG]::Protect('SID=S-1-5-21-...', $bytes)

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-07-01
#>
function Import-IDBridgeDpapiNGType {
    [CmdletBinding()]
    param ()

    if ('IDBridge.DpapiNG' -as [type]) { return }

    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace IDBridge
{
    public static class DpapiNG
    {
        [DllImport("ncrypt.dll", CharSet = CharSet.Unicode)]
        private static extern int NCryptCreateProtectionDescriptor(string pwszDescriptorString, uint dwFlags, out IntPtr phDescriptor);

        [DllImport("ncrypt.dll")]
        private static extern int NCryptCloseProtectionDescriptor(IntPtr hDescriptor);

        [DllImport("ncrypt.dll")]
        private static extern int NCryptProtectSecret(IntPtr hDescriptor, uint dwFlags, byte[] pbData, uint cbData, IntPtr pMemPara, IntPtr hWnd, out IntPtr ppbProtectedBlob, out uint pcbProtectedBlob);

        [DllImport("ncrypt.dll")]
        private static extern int NCryptUnprotectSecret(out IntPtr phDescriptor, uint dwFlags, byte[] pbProtectedBlob, uint cbProtectedBlob, IntPtr pMemPara, IntPtr hWnd, out IntPtr ppbData, out uint pcbData);

        [DllImport("kernel32.dll")]
        private static extern IntPtr LocalFree(IntPtr hMem);

        private const uint NCRYPT_SILENT_FLAG = 0x00000040;

        public static byte[] Protect(string descriptor, byte[] data)
        {
            IntPtr hDescriptor;
            int status = NCryptCreateProtectionDescriptor(descriptor, 0, out hDescriptor);
            if (status != 0) throw new InvalidOperationException(string.Format("NCryptCreateProtectionDescriptor failed for '{0}' (0x{1:X8})", descriptor, status));
            try
            {
                IntPtr blobPtr; uint blobLen;
                status = NCryptProtectSecret(hDescriptor, NCRYPT_SILENT_FLAG, data, (uint)data.Length, IntPtr.Zero, IntPtr.Zero, out blobPtr, out blobLen);
                if (status != 0) throw new InvalidOperationException(string.Format("NCryptProtectSecret failed (0x{0:X8})", status));
                try
                {
                    byte[] blob = new byte[blobLen];
                    Marshal.Copy(blobPtr, blob, 0, (int)blobLen);
                    return blob;
                }
                finally { LocalFree(blobPtr); }
            }
            finally { NCryptCloseProtectionDescriptor(hDescriptor); }
        }

        public static byte[] Unprotect(byte[] blob)
        {
            IntPtr hDescriptor; IntPtr dataPtr; uint dataLen;
            int status = NCryptUnprotectSecret(out hDescriptor, NCRYPT_SILENT_FLAG, blob, (uint)blob.Length, IntPtr.Zero, IntPtr.Zero, out dataPtr, out dataLen);
            if (status != 0) throw new InvalidOperationException(string.Format("NCryptUnprotectSecret failed (0x{0:X8})", status));
            try
            {
                byte[] data = new byte[dataLen];
                Marshal.Copy(dataPtr, data, 0, (int)dataLen);
                return data;
            }
            finally
            {
                LocalFree(dataPtr);
                if (hDescriptor != IntPtr.Zero) { NCryptCloseProtectionDescriptor(hDescriptor); }
            }
        }
    }
}
'@
}
