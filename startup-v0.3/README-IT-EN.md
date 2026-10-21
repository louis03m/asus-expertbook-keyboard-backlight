# ASUS B1502CBA — unified startup preview v0.3

## Italiano

**Preview sperimentale, BIOS 316 e 317 soltanto. Sul PC B1502CBA con BIOS 317 sono
stati verificati il ripristino automatico High prima della sessione, il ciclo
spento/medio/alto alla schermata di accesso e il passaggio al desktop. Non è una
validazione su altri PC; gli avvii da preferenza Off e Medium non sono stati
provati separatamente al boot, ma i relativi stati e la selezione sono coperti
dai test offline e dal ciclo fisico.**

Questa estensione richiede il ciclo a tre stati v0.2 già funzionante. Non modifica
servizi, driver o programmi ASUS. Usa un'attività SYSTEM all'avvio e la normale
attività elevata dell'utente dopo il login; non installa un servizio Windows.

- Ripristina **spento, medio oppure alto salvati**, senza scegliere alto per default.
- Prima della sessione, il tasto C7 seleziona fisicamente spento → medio → alto.
  ASUS elabora comunque il tasto: può esserci un breve passaggio intermedio.
- In questa fase la conferma è **solo fisica via WMI**: lo stato interno del servizio
  ASUS può differire. La scelta viene registrata separatamente e viene confermata
  nello stato ordinario solo dopo l'allineamento con l'agente ASUS al login.
- Dopo l'avvio della sessione, il worker rilascia il controllo e il ciclo desktop
  riallinea ASUS tramite i messaggi originali già studiati. Un solo listener attivo.
- Gli spegnimenti ASUS per inattività non sovrascrivono la preferenza. Non c'è un
  ciclo continuo di scritture per tenere accesa la luce contro un timeout ASUS.
- Se Windows prepara la sessione dietro la schermata bloccata, il ciclo desktop
  può funzionare già lì; questo non prova il percorso prima della sessione.

### Installazione su una v0.2 già funzionante

Estrarre tutto lo ZIP. Windows PowerShell 5.1 a 64 bit, come amministratore con
lo stesso account che possiede il ciclo attuale:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-Component.ps1 -LegacyDirectory 'C:\Program Files\AsusKeyboardBacklight-Experimental'
```

Per un'installazione in un'altra cartella, indicare il percorso reale del ciclo
esistente. L'installatore rifiuta modelli, BIOS, binari ASUS o attività inattesi.
Non sovrascrive una precedente installazione v0.3.

Codice protetto in `C:\Program Files\AsusKeyboardUnified-v0.3`; configurazione,
preferenza, log e backup XML in `C:\ProgramData\NeaLogic\AsusKeyboardUnified-v0.3`.
Solo SYSTEM e amministratori possono modificarli. Non usare cartelle modificabili
dagli utenti come sorgente di codice SYSTEM.

L'installazione verifica una lettura WMI come SYSTEM (nessuna scrittura luminosità),
arresta cooperativamente il vecchio ciclo e avvia il nuovo desktop. Il ripristino
desktop può cambiare la luminosità. **Arma una sola prova al prossimo avvio**;
non riavvia il computer. I file originali rimangono nella cartella precedente.

### Stato e prova reale

```powershell
Set-Location 'C:\Program Files\AsusKeyboardUnified-v0.3'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Manage-Component.ps1 -Action Status
```

Controllare `desktop-runtime\status.json`: `Listening`. Verificare visivamente il
ciclo dopo il login. Per il vero test prima della sessione, salvare il lavoro,
disconnettere l'utente e riavviare dalla schermata di accesso: non cambiare impostazioni
di sicurezza o accesso automatico. Non accedere subito: attendere 30 secondi SENZA
premere il tasto e verificare il livello salvato. Solo dopo provare tre pressioni,
distanziate di tre secondi, poi accedere e verificare conservazione della scelta.

Boot-status.json e i log Boot-* documentano la fase all'avvio. Una prova finita
con `UserSessionPresent` non prova la fase senza utente. Se arrivano errori, il
worker interrompe le scritture; non riprovare manualmente comandi EC. Il worker
prima della sessione termina dopo 30 minuti se nessuno accede; la prova non è una
gestione indefinita. La prova singola viene consumata anche se Windows ha già
preparato la sessione: per ripeterla usare `-Action ArmOnce`.

Solo dopo prova reale riuscita e conferma visiva si può abilitare l'avvio persistente:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Manage-Component.ps1 -Action EnablePersistentBoot -VisualBootConfirmed
```

### Tornare indietro

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Manage-Component.ps1 -Action Rollback
```

Attende il rilascio dei mutex senza terminare transazioni, ripristina le definizioni
originali delle attività e la preferenza confermata e riavvia il ciclo precedente.
Conserva file e log per diagnosi. Non cancellare le cartelle mentre un worker gira.
Il fallback spento/alto precedente rimane disponibile nella vecchia installazione.
Un errore del nuovo desktop richiede il rollback automatico verso il ciclo precedente;
un errore del solo boot lascia intatto il percorso desktop.

### Limiti e distribuzione

WMI modifica un parametro volatile EC: non flasha firmware. Il mutex protegge solo
i nostri programmi, non rende atomico l'accesso rispetto ad altri software OEM.
Non è provata la sincronizzazione della cache ASUS prima del login; viene eseguita
al login. Cambi rapidi utente, sessioni remote, sospensione/ripresa e pressioni rapide
non sono coperti dalla validazione. Non abbassare controlli, ACL o guardie di compatibilità.
Nessun binario ASUS, preferenza personale o log viene incluso nel pacchetto pubblico.
Leggere AI-adaptation-IT-EN.txt per l'analisi in sola lettura di altri modelli.

## English

**Experimental preview, B1502CBA BIOS 316/317 only. Automatic saved-High restoration
before the user session, the off/medium/high cycle at the sign-in screen and handoff
to the desktop were verified on the BIOS 317 development PC. Not verified on other
PCs. Separate cold boots starting from saved Off and Medium have not been visually
tested; those levels and selection logic are covered by offline checks and the
physical key cycle.**

Requires the working v0.2 three-state setup. Uses a SYSTEM startup task and the
owner's elevated logon task, retaining ASUS services/drivers and the previous
off/high fallback. No new Windows service or firmware flashing.

Restores the saved **Off, Medium or High** choice; missing or invalid preferences
never default to High. Before a user session, C7 cycles the physical levels through
WMI. Native ASUS handling may cause a brief intermediate level. **Pre-session
confirmation covers physical readback only**: ASUS's internal logical state may
differ. Pre-session choices are kept separately and synchronized through the ASUS
desktop agent before becoming ordinary confirmed preferences. One listener owns
control at a time. OEM idle-off does not overwrite the saved choice.

Extract the whole archive. From elevated 64-bit Windows PowerShell 5.1 under the
existing task owner's account:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-Component.ps1 -LegacyDirectory 'C:\Program Files\AsusKeyboardBacklight-Experimental'
```

Supply the actual legacy folder if different. Unexpected models, BIOS versions,
ASUS binaries, task owners and task actions are refused. Existing v0.3 directories
are not overwritten. Protected code: `C:\Program Files\AsusKeyboardUnified-v0.3`.
Protected state/logs/task backups: `C:\ProgramData\NeaLogic\AsusKeyboardUnified-v0.3`.
SYSTEM/admin write access only. Original scripts remain unchanged.

Setup first checks a bounded SYSTEM WMI read with no brightness writes, stops the
old cycle cooperatively and starts the new desktop (which can restore brightness).
It arms **one boot trial**, does not reboot and does not enable persistent boot.

From the installed v0.3 folder, `Manage-Component.ps1 -Action Status` displays
state. Confirm `Listening` in `desktop-runtime\status.json` and visually test the
desktop cycle. For actual pre-session testing, save work, sign out and restart
from the sign-in screen. Do not alter sign-in/security settings. Wait 30 seconds
without pressing the key and check the saved level; then test three keypresses
three seconds apart, sign in and check the final level is retained.

Inspect Boot-status.json and Boot-* logs. `UserSessionPresent` is not proof of a
pre-user-session test. One trial is consumed even if Windows prepares the session
early; use `Manage-Component.ps1 -Action ArmOnce` for another trial. The boot worker
stops after 30 minutes without login. On uncertainty it stops further writes.
No EC polling loop or repeated force-on against ASUS idle behavior.

Only after successful real boot and visual confirmation:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Manage-Component.ps1 -Action EnablePersistentBoot -VisualBootConfirmed
```

Rollback, from elevated PowerShell in the installed v0.3 folder:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Manage-Component.ps1 -Action Rollback
```

Waits for cooperative release, restores original task definitions and the confirmed
preference, and starts the legacy cycle. Retains files/logs. The old off/high fallback
is retained in the old installation. Desktop failure requests automatic rollback;
boot-only failure leaves desktop handling available.

The mutex serializes our clients only, not other OEM software. Pre-session ASUS cache
synchronization is not established and is deferred to login. Fast user switching,
remote sessions, suspend/resume and rapid presses are not validated. Keep all guards
and ACLs. No ASUS binaries or personal data are shipped. For other models, consult
AI-adaptation-IT-EN.txt for read-only investigation, never blind address/byte edits.

Repository: https://github.com/louis03m/asus-expertbook-keyboard-backlight
Pull requests remain disabled. Do not publish this preview as boot-validated until
the real pre-session device test is completed.

## Verifiche / Verification — 22 October 2026

9 script con sintassi verificata; 41 controlli offline di selezione/stato/rollback,
6 verifiche del passaggio delle scelte prelogin al desktop e 14 casi mock del helper
WMI. Lettura SYSTEM senza scrittura luminosità verificata. L'utente ha confermato
il ripristino High senza premere il tasto, il ciclo prima del login e la conservazione
di High dopo il login. La prima prova ha confermato il controllo fisico prima della
sessione; l'allineamento con la cache ASUS è avvenuto al login.

9 script syntax checks; 41 offline policy/state/rollback checks, 6 desktop pending-choice
checks and 14 mocked mailbox cases. Bounded SYSTEM read verified without brightness
writes. User confirmed automatic High restoration without a keypress, prelogin key
cycle and High remaining after login. Pre-session proof is physical readback;
ASUS logical synchronization occurred at login.

I 30 secondi indicati nella prova sono un tempo di osservazione, non un ritardo
programmato. The 30-second test wait is an observation window, not a programmed delay.

Per usare il precedente fallback Maximum, eseguire prima il rollback v0.3.
Run v0.3 rollback before using the legacy Maximum fallback.
