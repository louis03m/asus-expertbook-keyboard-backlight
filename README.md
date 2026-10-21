# ASUS ExpertBook keyboard backlight — B1502CBA / BIOS 316

**Experimental community workaround · v0.1-preview · Italiano / English**

## Italiano

### Cosa fa

Sul PC di sviluppo la tastiera era luminosa durante il boot, ma il software ASUS la portava a un livello debole in Windows. Il tasto originale permetteva soltanto acceso/spento.

Questo progetto aggiunge **tre stati con la stessa hotkey ASUS**:

**Spento → Medio → Alto → Spento**

Sono due intensità accese più lo spegnimento. La scelta confermata viene salvata e il programma la ripristina quando parte dopo il login. Rimangono attivi i servizi e le altre hotkey ASUS. Può esserci un breve passaggio a spento/medio prima dell'alto, perché anche ASUS elabora il tasto originale.

Non modifica o flasha il BIOS, non sostituisce driver e non applica patch ai programmi ASUS. Scrive un parametro **volatile del controller EC attraverso la mailbox WMI del firmware**: è un meccanismo specifico, non un'API pubblica ASUS per la luminosità.

### Compatibilità: leggere prima di avviare

- **ASUS ExpertBook B1502CBA**, BIOS **B1502CBA.316**.
- Percorso DriverStore e hash dei due binari ASUS devono corrispondere a quelli in `Assert-Compatibility.ps1`.
- Windows PowerShell **5.1 a 64 bit**, account amministratore e software ASUS originale attivo.
- **BIOS 317 e altri modelli/versioni sono rifiutati. Non rimuovere i controlli.**

Gli script non sono una correzione ufficiale ASUS o una soluzione universale. Il pacchetto non contiene binari ASUS, log, credenziali, indirizzi email o preferenze dell'autore.

### Download

Aprire **[Releases](https://github.com/louis03m/asus-expertbook-keyboard-backlight/releases)** e scaricare l'asset `AsusKeyboardBacklight-B1502CBA-BIOS316-v0.1-preview.zip`. Il file di progetto automatico “Source code” è una copia dei sorgenti; per seguire queste istruzioni usare lo ZIP del pacchetto allegato alla release.

SHA-256 del pacchetto:

```text
07ea2f2c21a446340dbd59206317886fb559f55471a6ca3d58aea1c07a7486e4
```

### 1. Estrarre e controllare, senza cambiare la tastiera

Estrarre **tutto** lo ZIP in una cartella. Aprire **Windows PowerShell**, entrare nella cartella che contiene gli script ed eseguire:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Check-Compatibility.ps1
```

Questo controllo legge modello, BIOS e hash; non invia comandi alla tastiera o al controller. Se fallisce, fermarsi: non cambiare i valori per farlo passare. Un esito positivo indica corrispondenza con la configurazione studiata, non garantisce la sicurezza su ogni esemplare.

### 2. Installare e attivare il ciclo

Aprire **Windows PowerShell come amministratore**, con il proprio account, tornare nella cartella estratta ed eseguire:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-Experimental.ps1
```

L'installatore crea una cartella nuova sotto `C:\Program Files\AsusKeyboardBacklight-Experimental`, copia gli script e configura due attività pianificate locali. Rifiuta cartelle o attività omonime già presenti: non sovrascrive un'installazione esistente.

- `Codex-ASUS-KeyboardCycle`: ciclo a tre stati, avviato al login con privilegi elevati e finestra nascosta, dopo un ritardo di cinque secondi.
- `Codex-ASUS-KeyboardMaximum`: correttore alternativo spento/alto, conservato come fallback e normalmente disabilitato quando è attivo il ciclo.

Non viene installato un nuovo servizio Windows. L'installazione avvia il programma e può cambiare la luminosità. Il ripristino della preferenza avviene **dopo il login**, non al boot o prima dell'accesso; attende anche la disponibilità dell'agente ASUS.

### 3. Verificare che sia operativo

Dalla cartella **installata**:

```powershell
Set-Location 'C:\Program Files\AsusKeyboardBacklight-Experimental'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Manage-AsusKeyboardMode.ps1 -Mode Status
```

Verificare `State = Listening` nel file `.analysis\cycle-runtime\status.json`. Un'attività creata o un avvio richiesto, da soli, non confermano il funzionamento. Premere poi la hotkey, distanziando le pressioni di circa due secondi, e verificare visivamente il ciclo. La prima pressione dipende dallo stato iniziale: non parte necessariamente da spento.

`keyboard-state.json` conserva la scelta confermata; `keyboard-state.json.previous` conserva il valore precedente. Non modificare i file per tentativi. I log in `.analysis` rimangono locali; non c'è telemetria di rete. Non pubblicare intere cartelle diagnostiche senza rimuovere percorsi e dati personali.

### Cambiare modalità o tornare indietro

Da PowerShell amministratore nella cartella **installata**, scegliere un solo comando:

```powershell
# Tre stati con memoria e ripristino dopo il login (modalità normale)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Manage-AsusKeyboardMode.ps1 -Mode Cycle

# Tre stati senza salvare/ripristinare la scelta
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Manage-AsusKeyboardMode.ps1 -Mode CycleWithoutMemory

# Correttore precedente: tasto ASUS spento/alto
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Manage-AsusKeyboardMode.ps1 -Mode Maximum

# Rimuovere entrambe le nostre attività e tornare alla gestione ASUS originale
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Remove-Experimental.ps1
```

La rimozione non interrompe forzatamente transazioni, non cambia servizi/driver ASUS e conserva file, log e luminosità attuale. Le pressioni successive tornano alla gestione ASUS. In caso di installazione parziale, eseguire la rimozione dalla cartella sotto Program Files, non da una seconda copia estratta.

### Verifiche e limiti della preview

Il ciclo e il salvataggio sono stati provati fisicamente sul PC di sviluppo; il rilancio del programma ha ripristinato tutti e tre gli stati salvati. **Il test completo riavvio/login di Windows resta da completare al momento di questa pubblicazione.** Il confezionamento pubblico, i controlli aggiuntivi e il nuovo installatore non sono stati installati su un secondo PC. Sono stati verificati la sintassi dei 13 script, otto controlli offline e il preflight in sola lettura sul PC di sviluppo.

Sospensione/ripresa, pressioni molto rapide e tutte le varianti hardware non sono completamente verificate. In caso di errore leggere i log; non ripetere scritture EC manualmente. Gli script di basso livello sono helper interni, non comandi generici per il controller.

### Un altro modello ASUS? AI come aiuto all'analisi

Leggere **[AI-adaptation-IT-EN.txt](AI-adaptation-IT-EN.txt)**. È possibile fornire i sorgenti a un assistente AI per studiare il proprio firmware **in sola lettura** e ricostruire parametri, sincronizzazione e hotkey. Non basta cambiare il nome del modello o fidarsi di indirizzi suggeriti dall'AI: servono evidenze sul firmware esatto e verifiche specifiche prima di qualsiasi prova attiva.

## English

### What it does

The development machine had a bright keyboard during boot, then dimmed when ASUS Windows software initialized it. Its original key only toggled on/off.

This project adds **three states using the same ASUS hotkey**:

**Off → Medium → High → Off**

These are two illuminated levels plus off. Confirmed choices are saved and restored when the watcher starts after login. ASUS services and other hotkeys remain active. A brief off/dim transition can remain before high because ASUS also processes the original keypress.

No BIOS flashing, replacement drivers or ASUS binary patches are involved. The program writes a **volatile EC parameter through an existing firmware WMI mailbox**. This is a model-specific mechanism, not a documented ASUS brightness API.

### Requirements and scope

- **ASUS ExpertBook B1502CBA / BIOS B1502CBA.316** only.
- Exact ASUS DriverStore paths and image hashes checked by `Assert-Compatibility.ps1`.
- **64-bit Windows PowerShell 5.1**, administrator account, original ASUS software running.
- **BIOS 317 and other configurations are rejected. Do not bypass the guards.**

This is an independent experimental workaround, not an official or universal ASUS fix. No ASUS binaries, personal logs, credentials, email addresses or saved preferences are distributed.

### Download and read-only check

Open **[Releases](https://github.com/louis03m/asus-expertbook-keyboard-backlight/releases)** and download the attached `AsusKeyboardBacklight-B1502CBA-BIOS316-v0.1-preview.zip` asset. Use this package, rather than the automatically generated source archive, for the instructions below. Its SHA-256 is listed above.

Extract the **whole ZIP**, open Windows PowerShell in the folder containing the scripts and run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Check-Compatibility.ps1
```

This reads model, BIOS and hashes without sending keyboard/controller commands. Stop if it fails. Passing confirms a configuration match, not safety on every individual machine.

### Install and enable

Open **Windows PowerShell as administrator under your own account**, return to the extracted script folder and run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-Experimental.ps1
```

Creates a fresh `C:\Program Files\AsusKeyboardBacklight-Experimental` folder and local scheduled tasks. Existing folders/tasks with the same names are refused. `Codex-ASUS-KeyboardCycle` runs the cycle after login, elevated and hidden with a five-second trigger delay. `Codex-ASUS-KeyboardMaximum` is retained as the off/high fallback and normally disabled while the cycle is active. No new Windows service is installed.

Setup starts the watcher and may change brightness. Restoration occurs **after login**, not during boot or at the sign-in screen, and waits for the original ASUS agent.

### Check operation

From the **installed** directory:

```powershell
Set-Location 'C:\Program Files\AsusKeyboardBacklight-Experimental'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Manage-AsusKeyboardMode.ps1 -Mode Status
```

Confirm `State = Listening` in `.analysis\cycle-runtime\status.json`, then visually test the hotkey, allowing about two seconds between presses. A task being registered or a start being requested does not prove the watcher is working. The first transition depends on the current state.

`keyboard-state.json` stores the confirmed preference; `.previous` stores its predecessor. Local logs are under `.analysis`. There is no network telemetry. Remove personal paths/data before sharing diagnostics.

### Modes and removal

In an elevated Windows PowerShell from the **installed folder**, select one command:

```powershell
# Three states with saved preference and restoration after login
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Manage-AsusKeyboardMode.ps1 -Mode Cycle

# Three states without saving/restoring the preference
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Manage-AsusKeyboardMode.ps1 -Mode CycleWithoutMemory

# Original workaround: ASUS off/high toggle
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Manage-AsusKeyboardMode.ps1 -Mode Maximum

# Remove our tasks and return subsequent keypresses to native ASUS handling
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Remove-Experimental.ps1
```

Removal does not force-terminate transactions or change ASUS drivers/services. Files, logs and current brightness are retained. For a partial installation, run removal from Program Files, not from another extracted copy.

### Validation and limitations

The cycle and preference saves were physically tested on the development computer; restarting the watcher restored each saved state. **A full Windows reboot/login test remains pending at publication.** The public packaging, extra guards and new installer have not been installed on a second computer. All 13 scripts passed syntax checks, eight offline guard checks passed, and the read-only compatibility check passed on the development computer.

Suspend/resume, rapid presses and all hardware variants are not fully tested. Read logs on failure; do not retry low-level EC writes manually. The mailbox/state helpers are internal implementation details, not generic controller commands.

For another ASUS, read **[AI-adaptation-IT-EN.txt](AI-adaptation-IT-EN.txt)**. An AI assistant can help analyze your exact firmware in read-only mode, including synchronization and hotkeys. Changing the model string or trusting AI-generated addresses is not a valid adaptation; exact-firmware evidence and device-specific validation are required before active testing.

## References / Riferimenti

- [Official B1502CBA BIOS downloads](https://www.asus.com/ca-en/supportonly/b1502cba/helpdesk_bios/): ASUS lists 317, but we have not tested it; the retrieved public notes do not explicitly mention this brightness issue.
- [B1502 user report on LaptopMedia](https://laptopmedia.com/es/review/asus-expertbook-b1-b1502-review-business-features-on-the-budget/p2/).
- [ExpertBook dim-backlight discussion on Reddit](https://www.reddit.com/r/ASUS/comments/1s0sdul/expert_book_keyboard_light_too_dim_please_help/).

This repository is for distribution and documentation. Contributions and pull requests are not requested; no third-party collaborator access is granted.
