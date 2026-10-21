ASUS ExpertBook B1502CBA / BIOS 316 / 317 - Experimental community package
Version 0.2-preview - 2026-10-22

ITALIANO
========
Problema: luce intensa durante il boot, debole dopo l'avvio del software ASUS;
il tasto originale offre soltanto acceso/spento.
Risultato osservato sul PC di sviluppo: spento -> medio -> alto -> spento con
la stessa hotkey, mantenendo servizi e hotkey ASUS. Possibile breve passaggio
a spento/medio tra medio e alto. Nessun BIOS flashato o driver modificato.
Il programma scrive un parametro VOLATILE del controller EC tramite la mailbox
WMI del firmware. Non e' un'API ASUS pubblica e non e' una soluzione universale.

Compatibilita' volutamente stretta:
- ASUS ExpertBook B1502CBA, BIOS B1502CBA.316 oppure B1502CBA.317.
- Stesso percorso DriverStore e stessi hash di AsusOptimization.exe e
  AsusOptimizationStartupTask.exe verificati da Assert-Compatibility.ps1.
- Windows PowerShell 5.1 a 64 bit, account amministratore, software ASUS attivo.
Su altre versioni/modelli il controllo si FERMA. Non rimuoverlo.
Nessun binario ASUS e' incluso. Nessun log, email o stato personale e' incluso.

Prima verifica (sola lettura): estrarre TUTTO lo ZIP, aprire Windows PowerShell
nella cartella estratta ed eseguire:
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Check-Compatibility.ps1
Il superamento indica una corrispondenza con la configurazione provata,
non una garanzia di assenza di rischi o di compatibilita' con altri PC.

Installazione SPERIMENTALE, soltanto dopo controllo riuscito e lettura dei limiti:
aprire Windows PowerShell come amministratore con il proprio account ed eseguire:
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-Experimental.ps1
Crea una cartella NUOVA sotto Program Files e due attivita' pianificate locali.
Non sovrascrive cartelle o attivita' preesistenti con gli stessi nomi.
L'installazione avvia il programma e puo' cambiare la luminosita'.
Il fallback spento/alto e' conservato; il ciclo salva l'ultima scelta confermata.
Controllare State=Listening in .analysis\cycle-runtime\status.json nella cartella
installata, poi verificare visivamente le hotkey. Un avvio richiesto non prova
che il programma sia operativo. I log rimangono locali, senza telemetria di rete.
Il ripristino ha effetto dopo il login, non durante il boot o prima dell'accesso.

Ritorno al correttore spento/alto, dalla cartella installata in PowerShell admin:
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Manage-AsusKeyboardMode.ps1 -Mode Maximum
Rimozione delle nostre attivita', dalla cartella INSTALLATA in PowerShell admin:
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Remove-Experimental.ps1
Non termina forzatamente una transazione. Conserva file/log e luminosita'
attuale; lascia ad ASUS la gestione originale delle pressioni successive.
In caso di installazione parziale usare la rimozione dalla cartella sotto
Program Files, non da una seconda copia estratta in Download.

BIOS 316: ciclo, memoria e ripristino dopo riavvio/login verificati sul PC di sviluppo. BIOS 317: confronto del firmware EC e dei metodi ACPI/WMI pertinenti, ripristino in sessione e ciclo spento/medio/alto verificati sullo stesso PC. Un ulteriore riavvio/login con il programma aggiornato per 317 resta da verificare. Il pacchetto pubblico e il nuovo installatore non sono stati installati su un secondo PC. I controlli offline verificano compatibilità, rifiuto delle configurazioni sconosciute e migrazione delle preferenze; non inviano comandi al controller.
Sospensione/ripresa e pressioni rapide non completamente verificate.
Gli helper Set-AsusKeyboardState.ps1 e Wmi-Maximum-OneShot.ps1 sono interni:
non usarli come comandi generici e non adattare indirizzi/valori per tentativi.
Leggere AI-adaptation-IT-EN.txt per l'adattamento assistito a un altro modello.

ENGLISH
=======
Symptom: bright at boot, dim after ASUS Windows software initializes it;
the original hotkey only toggles on/off.
Observed on the development machine: off -> medium -> high -> off with the same
hotkey, retaining ASUS services and other hotkeys. A brief off/dim transition
may occur between medium and high. No BIOS flashing or driver patching.
This uses an existing firmware WMI mailbox to change a VOLATILE EC parameter.
It is not a documented ASUS brightness API or a universal fix.

Only B1502CBA / BIOS B1502CBA.316 or B1502CBA.317 plus the exact ASUS paths/image hashes checked
in Assert-Compatibility.ps1 are accepted. Requires 64-bit Windows PowerShell
5.1, an administrator account and the original ASUS software running.
Other configurations must STOP. Do not bypass the checks.
No ASUS binaries, personal state, email addresses or diagnostic logs are shipped.

Extract the WHOLE archive. Read-only compatibility check from the extracted folder:
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Check-Compatibility.ps1
Passing means a match to the tested configuration, not a safety guarantee.
Experimental install, in an elevated Windows PowerShell under your own account:
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-Experimental.ps1
Creates a fresh Program Files folder and two local scheduled tasks. Refuses
existing tasks/folders. Starts the watcher and may change keyboard brightness.
The off/high fallback is retained. Confirm State=Listening in the installed
.analysis\cycle-runtime\status.json, then visually test the key cycle.
Saved preferences restore after login, not during boot or at the login screen.
There is no network telemetry; runtime logs remain local.

Off/high fallback, elevated PowerShell from the INSTALLED folder:
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Manage-AsusKeyboardMode.ps1 -Mode Maximum
Remove our scheduled tasks, elevated PowerShell from the INSTALLED folder:
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Remove-Experimental.ps1
Removal does not force-terminate a transaction. Files/logs and current brightness
are retained; subsequent keypresses are handled by the original ASUS software.
For a partial install, run removal from Program Files, not a second extracted copy.

BIOS 316: cycle, saved preferences and restoration after Windows reboot/login verified on the development PC. BIOS 317: relevant EC firmware and ACPI/WMI methods compared, in-session restoration and off/medium/high cycle verified on the same PC. Another full reboot/login with the updated 317 watcher remains to be verified. The public package and installer have not been installed on a second PC. Offline checks cover compatibility, refusal of unknown configurations and preference migration; they send no controller commands.
Suspend/resume and rapid presses are not fully tested.
The low-level state/mailbox scripts are internal helpers, not generic commands.
See AI-adaptation-IT-EN.txt before investigating another ASUS model.

Sources / fonti:
https://www.asus.com/ca-en/supportonly/b1502cba/helpdesk_bios/
https://www.reddit.com/r/ASUS/comments/1s0sdul/expert_book_keyboard_light_too_dim_please_help/
https://laptopmedia.com/es/review/asus-expertbook-b1-b1502-review-business-features-on-the-budget/p2/

BIOS 317 was checked on the development PC; this remains an independent workaround.
This is an independent experimental community project, not an ASUS product.

AGGIORNAMENTO / UPDATE
Preferenze 316 e 317 accettate; migrazione dopo ripristino riuscito, backup .previous.
Prima di reinstallare: rimuovere le nostre attivita dalla vecchia cartella, conservarla
come backup, installare la nuova copia e scegliere il livello con la hotkey. Non
eseguire due copie insieme. La nuova installazione non importa lo stato precedente.
Per tornare indietro rimuovere prima le nuove attivita; v0.1 accetta solo BIOS 316.

316/317 preferences accepted; migration after successful restoration, .previous backup.
Before reinstalling, remove our tasks from the old installed folder, retain that
folder as a backup, install the new copy and choose the level again with the hotkey.
Do not run two copies together. Fresh installs do not import the old preference.
For rollback remove the new tasks first; v0.1 accepts BIOS 316 only.

Repository: https://github.com/louis03m/asus-expertbook-keyboard-backlight
Pull request disabilitate / Pull requests disabled. Public forks remain possible.

MODALITA / MODES
Da PowerShell amministratore nella cartella installata / Elevated PowerShell,
from the installed folder:
  Set-Location 'C:\Program Files\AsusKeyboardBacklight-Experimental'
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Manage-AsusKeyboardMode.ps1 -Mode Status
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Manage-AsusKeyboardMode.ps1 -Mode Cycle
Cycle: spento -> medio -> alto -> spento, memoria e ripristino dopo il login.
Cycle: off -> medium -> high -> off, saved preference restored after login.
Per tre stati senza memoria / For three states without memory:
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Manage-AsusKeyboardMode.ps1 -Mode CycleWithoutMemory
Non avviare manualmente gli helper di basso livello / Do not run low-level helpers.
