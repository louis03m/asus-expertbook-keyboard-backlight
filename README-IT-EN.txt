ASUS ExpertBook B1502CBA / BIOS 316 - Experimental community package
Version 0.1-preview - 2026-10-21

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
- ASUS ExpertBook B1502CBA, BIOS B1502CBA.316.
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

Verifiche e limiti: ciclo e salvataggio provati fisicamente sul PC originale;
rilancio con ripristino di tutti e tre gli stati provato. Al momento di questa
pubblicazione il login dopo riavvio completo resta da verificare. La confezione
pubblica e il nuovo installatore NON sono stati installati su un secondo PC.
Verificati sintassi e controlli offline; sospensione/ripresa, pressioni molto
rapide e tutte le varianti hardware non sono coperti da una verifica completa.
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

Only B1502CBA / BIOS B1502CBA.316 plus the exact ASUS paths/image hashes checked
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

Validation: the original machine's cycle and preference saves were visually
tested; restarting the watcher restored each of the three saved states. Full
Windows reboot/login verification remains pending at publication. The public
packaging/new installer has NOT been installed on a second computer. Syntax and
offline guards were checked; suspend/resume and rapid presses are not fully tested.
The low-level state/mailbox scripts are internal helpers, not generic commands.
See AI-adaptation-IT-EN.txt before investigating another ASUS model.

Sources / fonti:
https://www.asus.com/ca-en/supportonly/b1502cba/helpdesk_bios/
https://www.reddit.com/r/ASUS/comments/1s0sdul/expert_book_keyboard_light_too_dim_please_help/
https://laptopmedia.com/es/review/asus-expertbook-b1-b1502-review-business-features-on-the-budget/p2/

ASUS lists BIOS 317, but its retrieved notes mention performance/security only;
we have not tested 317 or confirmed a keyboard-brightness fix in it.
This is an independent experimental community project, not an ASUS product.
