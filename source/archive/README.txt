ARCHIVE - superseded / historical POC artifacts (moved 2026-07-15)
Internal request/ticket material was removed for publication; role-based asks are summarized in docs\prerequisites.md. To restore any file: Move-Item .\archive\<sub>\<file> .\ (or .\scripts\)

CURRENT CURATION (2026-08-20)
  Active documentation is indexed by docs\README.md and STATUS.md. This archive preserves
  pre-deployment build material without keeping it in the active navigation surface.

  docs\planning\          Original checklists and risk register.
  docs\network\           Firewall allowlist diff and point-in-time fabric fallback/diagnostics.
  docs\runbooks\          One-time deployment wizard, card-swap, and domain-cutover procedures.
  docs\test-plans\        Plan-only test contracts superseded by executed sprint and integration evidence.

  Archive material is retained for historical reconstruction. Do not run a script or follow a procedure from
  this tree without first comparing it to the current runbooks, decisions, and status board.

docs\
  secureboot_procedure.txt          Secure Boot saga - resolved (reimage-with-SB-ON is the fix)
  secureboot_recovery_options.txt   Ranked SB recovery options - saga closed
  poc_doc_gap_evidence.txt          Documentation-failure evidence trail (historical)
  poc_prereq_checklist.notes.txt    Legacy annotated Phase 0 checklist
  node_bootstrap_paste.txt          Replaced by per-node scripts\nodeXX-console-paste.ps1

scripts\
  Repair-Node05DotNetLcu.ps1        node05 .NET LCU fix - node05 done
  Repair-Node05FromMsu.ps1          node05 MSU repair - node05 done
  Invoke-NodeUpdate.ps1             WU-over-WinRM runner - DO NOT USE (WU forbidden on Azure Local)
  probe_vpn.ps1                     one-off VPN probe
  probe_100gbe.ps1                  one-off 100GbE probe
  probe_100gbe_media.ps1            one-off 100GbE media probe
