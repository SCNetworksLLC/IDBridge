<#
.SYNOPSIS
Grant an account the local 'Log on as a batch job' right (internal).

.DESCRIPTION
Internal helper for Register-IDBridgeScheduledTask. Grants SeBatchLogonRight — the right
a scheduled-task principal needs — to the given account in the local security policy,
through a thin P/Invoke wrapper over advapi32.dll (LsaOpenPolicy / LsaAddAccountRights);
there is no in-box cmdlet for user rights. The type is compiled once per session.
Granting a right the account already holds succeeds unchanged, so the call is idempotent.

The grant is LOCAL: when a GPO manages 'Log on as a batch job', the GPO's list overwrites
it on the next policy refresh — the caller warns about that. Requires an elevated session.

.PARAMETER Identity
Account to grant the right, e.g. 'DOMAIN\gMSA-IDBridge$'.

.EXAMPLE
Grant-IDBridgeBatchLogonRight -Identity 'DOMAIN\gMSA-IDBridge$'

.NOTES
   Created by: Sam Cattanach
   Modified: 2026-08-27
#>
function Grant-IDBridgeBatchLogonRight {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Identity
    )

    if (-not ('IDBridge.LsaRights' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace IDBridge
{
    public static class LsaRights
    {
        [StructLayout(LayoutKind.Sequential)]
        private struct LSA_OBJECT_ATTRIBUTES
        {
            public int Length; public IntPtr RootDirectory; public IntPtr ObjectName;
            public uint Attributes; public IntPtr SecurityDescriptor; public IntPtr SecurityQualityOfService;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct LSA_UNICODE_STRING
        {
            public ushort Length; public ushort MaximumLength; public IntPtr Buffer;
        }

        [DllImport("advapi32.dll")]
        private static extern uint LsaOpenPolicy(IntPtr systemName, ref LSA_OBJECT_ATTRIBUTES objectAttributes, uint desiredAccess, out IntPtr policyHandle);

        [DllImport("advapi32.dll")]
        private static extern uint LsaAddAccountRights(IntPtr policyHandle, byte[] accountSid, LSA_UNICODE_STRING[] userRights, uint countOfRights);

        [DllImport("advapi32.dll")]
        private static extern uint LsaNtStatusToWinError(uint status);

        [DllImport("advapi32.dll")]
        private static extern uint LsaClose(IntPtr policyHandle);

        private const uint POLICY_CREATE_ACCOUNT = 0x00000010;
        private const uint POLICY_LOOKUP_NAMES   = 0x00000800;

        public static void AddRight(byte[] sid, string rightName)
        {
            var attributes = new LSA_OBJECT_ATTRIBUTES();
            IntPtr policy;
            uint status = LsaOpenPolicy(IntPtr.Zero, ref attributes, POLICY_CREATE_ACCOUNT | POLICY_LOOKUP_NAMES, out policy);
            if (status != 0) throw new System.ComponentModel.Win32Exception((int)LsaNtStatusToWinError(status));
            try
            {
                var right = new LSA_UNICODE_STRING
                {
                    Buffer = Marshal.StringToHGlobalUni(rightName),
                    Length = (ushort)(rightName.Length * 2),
                    MaximumLength = (ushort)((rightName.Length + 1) * 2)
                };
                try
                {
                    status = LsaAddAccountRights(policy, sid, new[] { right }, 1);
                    if (status != 0) throw new System.ComponentModel.Win32Exception((int)LsaNtStatusToWinError(status));
                }
                finally { Marshal.FreeHGlobal(right.Buffer); }
            }
            finally { LsaClose(policy); }
        }
    }
}
'@
    }

    try {
        $sid = ([System.Security.Principal.NTAccount]$Identity).Translate([System.Security.Principal.SecurityIdentifier])
        $sidBytes = [byte[]]::new($sid.BinaryLength)
        $sid.GetBinaryForm($sidBytes, 0)
        [IDBridge.LsaRights]::AddRight($sidBytes, 'SeBatchLogonRight')
        Write-Log -Message "Task: Granted 'Log on as a batch job' (SeBatchLogonRight) to '$Identity'."
    }
    catch { Throw "Granting 'Log on as a batch job' to '$Identity' failed (elevated session required): $($_)" }
}
