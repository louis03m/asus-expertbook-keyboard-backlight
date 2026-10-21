# ASUS ExpertBook B1502CBA — v0.3.1-preview

**Pacchetto unico / Standalone package · BIOS 316 / 317 · Italiano / English**

## Italiano

Una sola installazione per **spento → medio → alto → spento** con la hotkey ASUS,
memoria dell'ultima scelta, ripristino prima della sessione Windows e gestione dopo
il login. **Non serve installare prima la 0.2 o la 0.3.**

Sul PC B1502CBA con BIOS 317 sono stati verificati il ripristino automatico High prima
della sessione, il ciclo completo prima del login e il passaggio al desktop con High
conservato. Non è una validazione su altri PC. Gli avvii separati da preferenza Off e
Medium e sospensione/ripresa non sono completamente verificati. È un workaround
sperimentale indipendente da ASUS, non una correzione ufficiale o universale.

### 1. Scaricare ed estrarre

Scaricare lo ZIP **v0.3.1 standalone** dagli asset della
[release](https://github.com/louis03m/asus-expertbook-keyboard-backlight/releases/tag/v0.3.1-preview)
ed estrarlo interamente. Usare lo ZIP allegato, non l'archivio automatico Source code.

Requisiti: B1502CBA, BIOS B1502CBA.316 o B1502CBA.317, esatti binari ASUS verificati
da Assert-Compatibility.ps1, software ASUS attivo, Windows PowerShell 5.1 a 64 bit
e account amministratore. Se i controlli falliscono, fermarsi: non rimuoverli e non
copiare indirizzi EC su altri modelli.

### 2. Un solo comando per installare o aggiornare

Aprire **Windows PowerShell a 64 bit come amministratore**, con il proprio account,
nella cartella estratta:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-Component.ps1
```

- **Prima installazione:** crea le due attività necessarie e legge il livello attuale
  come scelta iniziale. Non imposta High per default. Poi scegliere il livello con la hotkey.
- **0.2 già presente:** rileva il percorso dall'attività, importa la scelta e conserva
  file e definizioni originali per il rollback. Nessun download aggiuntivo.
- **0.3/0.3.1 già presente:** aggiorna in posizione con backup del codice, arresto
  cooperativo e conservazione di preferenza e modalità di avvio persistente.
- Attività parziali, utenti/percorsi inattesi o cartelle non protette vengono rifiutati.

Solo per scegliere esplicitamente il livello alla prima installazione:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-Component.ps1 -InitialLevel High
```

Valori ammessi: Off, Medium, High. Il parametro viene rifiutato negli aggiornamenti,
che devono mantenere la scelta esistente. L'installazione verifica una lettura WMI
come SYSTEM senza scrivere la luminosità; l'avvio del desktop può poi ripristinare il
livello. Non esegue riavvii automatici.

### 3. Verificare e attivare l'avvio

Codice: `C:\Program Files\AsusKeyboardUnified-v0.3`. Stato, log e backup:
`C:\ProgramData\NeaLogic\AsusKeyboardUnified-v0.3`. Il nome cartella indica la famiglia
0.3, compresa la 0.3.1. Solo SYSTEM e amministratori possono modificare queste cartelle.

```powershell
Set-Location 'C:\Program Files\AsusKeyboardUnified-v0.3'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Manage-Component.ps1 -Action Status
```

Verificare desktop `Listening` e provare visivamente il ciclo, circa tre secondi fra
le pressioni. Scegliere il livello da ricordare. Una nuova installazione prepara
**un solo avvio di prova**: salvare il lavoro, disconnettere l'utente e riavviare dalla
schermata di accesso. Aspettare 30 secondi senza premere il tasto, controllare il
livello salvato, provare il ciclo e accedere. I 30 secondi sono una finestra di
osservazione, non un ritardo programmato. Non cambiare impostazioni di sicurezza/login.

Dopo una prova riuscita sul proprio PC, abilitare tutti gli avvii:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Manage-Component.ps1 -Action EnablePersistentBoot -VisualBootConfirmed
```

Richiede anche readback e passaggio al desktop nei log. Per ripetere la prova usare
`-Action ArmOnce`. Un aggiornamento conserva la modalità di avvio già scelta.

### Tornare indietro

Da PowerShell amministratore nella cartella installata:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Manage-Component.ps1 -Action Rollback
```

Da un'installazione autonoma rimuove solo le nostre attività e restituisce i tasti ad
ASUS. Da una migrazione della 0.2 ripristina le definizioni originali e la preferenza
confermata del correttore precedente. Un aggiornamento fallito tenta di ripristinare
il codice precedente. Attende il rilascio dei mutex, senza terminare transazioni a metà.
File, stato e log rimangono disponibili. Per il vecchio fallback Maximum eseguire prima
il rollback. Nessun driver o servizio ASUS viene modificato.

### Funzionamento e limiti

Prima del login il worker SYSTEM conferma il **livello fisico** via WMI; lo stato interno
ASUS può differire. La scelta viene conservata separatamente e il desktop la riallinea
tramite l'agente ASUS prima di confermarla nello stato ordinario. Non invia messaggi al
desktop protetto. Può esserci un breve livello intermedio perché anche ASUS gestisce il tasto.

Gli spegnimenti temporanei ASUS non cancellano la preferenza. Nessun polling EC continuo
per contrastare l'inattività. Il worker prelogin termina dopo 30 minuti senza accesso.
Il mutex serializza i nostri client, non altri software OEM. Errori o risultati incerti
fermano ulteriori scritture. Cambi rapidi utente, sessioni remote, sospensione e pressioni
molto rapide non sono completamente verificati.

Modifica un parametro **volatile EC**, non flasha BIOS e non applica patch ASUS. Nessun
binario ASUS, log personale o preferenza dell'autore è incluso. Per altri modelli leggere
AI-adaptation-IT-EN.txt: l'AI può aiutare nell'analisi in sola lettura, non garantire compatibilità.

## English

One standalone package provides the original-key **off → medium → high → off** cycle,
saved choice, pre-session restoration and desktop handling. **No prior v0.2/v0.3 installation
or download is required.**

Automatic saved-High restoration before the user session, the full prelogin cycle and
desktop handoff retaining High were verified on the BIOS 317 development B1502CBA.
Other PCs, separate saved-Off/Medium boots and suspend/resume remain incompletely tested.
Independent experimental workaround, not an official or universal ASUS fix.

### Download, install or update

Extract the attached **v0.3.1 standalone ZIP** from the
[release](https://github.com/louis03m/asus-expertbook-keyboard-backlight/releases/tag/v0.3.1-preview).
Use the attached package rather than the automatic Source code archive. Requires B1502CBA,
BIOS B1502CBA.316/317, exact ASUS images checked by Assert-Compatibility.ps1, original ASUS
software running, 64-bit Windows PowerShell 5.1 and an administrator account. Stop on guard
failures; do not bypass them or copy EC addresses to other models.

From elevated **64-bit Windows PowerShell under your own account**, in the extracted folder:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-Component.ps1
```

- **Fresh install:** creates its own two tasks and captures current brightness; never
  defaults to High. Choose the preferred level with the key afterward.
- **Existing v0.2:** automatically detects its directory, imports its choice and retains
  original scripts/task definitions for rollback. No extra download.
- **Existing v0.3/0.3.1:** backs up code, stops cooperatively and updates in place,
  preserving the preference and persistent-boot setting.
- Partial, unrelated, foreign-owner or unprotected installations are refused.

Optionally select an initial level on a fresh install only:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-Component.ps1 -InitialLevel High
```

Allowed: Off, Medium, High. Updates refuse this option to preserve existing choices.
Setup first verifies a bounded SYSTEM WMI read without brightness writes; desktop startup
can then restore brightness. No automatic reboot.

### Check and enable startup

Code: `C:\Program Files\AsusKeyboardUnified-v0.3`. State/logs/backups:
`C:\ProgramData\NeaLogic\AsusKeyboardUnified-v0.3`. Directory name denotes the 0.3 family,
including 0.3.1. Only SYSTEM/admins can modify these folders.

```powershell
Set-Location 'C:\Program Files\AsusKeyboardUnified-v0.3'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Manage-Component.ps1 -Action Status
```

Confirm desktop `Listening`, test the key cycle three seconds apart and choose the saved
level. New installs arm **one boot trial**. Save work, sign out and restart from the sign-in
screen to avoid Windows preparing a user session early. Wait 30 seconds without pressing
the key, check the saved level, test the cycle and sign in. This is an observation window,
not a programmed delay. Do not alter sign-in/security settings.

After successful visual validation on your PC:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Manage-Component.ps1 -Action EnablePersistentBoot -VisualBootConfirmed
```

Requires matching firmware readback and handoff logs. Use `-Action ArmOnce` for another
trial. Updates preserve the existing boot mode.

### Rollback / removal

From elevated PowerShell in the installed folder:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Manage-Component.ps1 -Action Rollback
```

Fresh installs remove only our tasks and return the key to native ASUS handling. A migrated
v0.2 install restores its original tasks and confirmed choice. Failed in-place updates
attempt to restore previous code. Waits cooperatively; no forced transaction termination.
Files/state/logs retained; no ASUS service/driver changes. Roll back before using a legacy
Maximum fallback.

### Limits

Prelogin confirmation is **physical WMI readback**; ASUS internal state can differ. Desktop
synchronizes ASUS before confirming the ordinary preference. No protected-desktop messaging.
A brief intermediate level can remain because ASUS also handles the key. Temporary idle-off
does not erase the choice; no continuous EC polling. The prelogin worker stops after 30
minutes without login. The mutex serializes only our clients, not other OEM software.
Errors/uncertain results stop further writes. Fast user switching, remote sessions,
suspend/resume and rapid keys are not fully validated.

Volatile EC parameter only; no BIOS flash or ASUS binary patch. No ASUS binaries, personal
logs or author preferences shipped. For another model, use AI-adaptation-IT-EN.txt for
read-only investigation; AI does not establish EC safety.

Repository: https://github.com/louis03m/asus-expertbook-keyboard-backlight

Pull requests disabled; no collaborator access granted. Public forks remain possible.
