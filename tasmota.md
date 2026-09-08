# Tasmota su WHY2025 / EMF2026 Badge

Questo documento descrive come far girare **Tasmota** (in alternativa al firmware ESP-IDF/LVGL
ufficiale di questo repo) sul badge WHY2025 / EMF2026, riusando tutto l'hardware presente sul
PCB. Le informazioni sui GPIO e sui registri sono estratte dal firmware ufficiale
(`main/badge/led.c`, `main/badge/led.h`, `main/badge/ui.h`, `sdkconfig.emf2026-badge`,
`components/lvgl_esp32_drivers/lvgl_tft/st7789.c`) e dal `README.md`; i codici componente e il
comportamento di Tasmota dalla documentazione ufficiale (pagine *Components*, *Displays*,
*Universal Display Driver*, *Berry*, *BUILDS*) e dai binari pubblicati su `ota.tasmota.com`.

**Stato (settembre 2026): verificato sul badge.** Con una build TasmoCompiler (vedi *Build custom*)
funzionano LED WS2812, pulsanti con le regole di *Pulsanti*, display via Universal Display Driver
e retroilluminazione via Berry/AW9523B; il `display.ini` verificato è in
[`tasmota/display.ini`](tasmota/display.ini). Non ancora provati: TSC2007 e connettori `RGB*`.
Consigliato `I2CDriver32 0` contro il driver MLX90614 che interroga `0x5A` (vedi *Cosa non è
supportato*).

> **Attenzione concettuale**: questa è una board custom da conferenza (MCU ESP32-C3 + display +
> LED + I2C expander), non un dispositivo "smart plug/switch" tipico di Tasmota. Flashare Tasmota
> **sostituisce interamente** il firmware ufficiale: radar BLE, giochi (Snake, Space Invaders),
> sync schedule via Wi-Fi, animazioni rainbow, web UI del badge, ecc. andranno persi.
> Per tornare al firmware originale: `pio run -e emf2026-badge -t upload` seguito da
> `pio run -e emf2026-badge -t uploadfs` (procedura del README, riscrive bootloader, tabella
> partizioni e filesystem).

## Hardware e mappa GPIO (ESP32-C3)

| GPIO | Funzione sul PCB | Connettore / pin | Note |
|---|---|---|---|
| 0 | I2C **SCL** | "I2C" pin 2 | bus verso **un** AW9523B (indirizzo `0x5A`: backlight + connettori RGB*) e il TSC2007 (touch, indirizzo tipico `0x48`) |
| 1 | I2C **SDA** | "I2C" pin 3 | idem |
| 2 | SPI **MISO** (SDO del display) | "SPI" pin 6 | il firmware lo configura, ma il display viene usato solo in scrittura: Tasmota non ne ha bisogno (vedi `Option A3` sotto) |
| 3 | Display **RESET** | interno | ST7789 |
| 4 | Display **DC** (data/command) | "SPI" pin 4 | ST7789 |
| 5 | **WS2812** data-in | interno (7 LED frontali) | il DOUT dell'ultimo LED esce sul pin 4 ("1W") del connettore "I2C" |
| 6 | SPI **CLK** | "SPI" pin 5 | ST7789, SPI hardware |
| 7 | SPI **MOSI** | "SPI" pin 2 | ST7789 |
| 8 | **Button1** = DOWN (rotella destra / pressione centrale destra) | "RS232" pin 4 o 5 | `ui.h`: `BUTTON_1 0x08 // DOWN`; attivo basso, pull-up interno. **Strapping**: per il download mode deve restare alto (pulsante rilasciato). Il README chiama i due segnali "button A/B" ma non dice quale sia quale |
| 9 | **Button2** = UP (rotella sinistra / pressione centrale sinistra) | "RS232" pin 4 o 5 | `ui.h`: `BUTTON_2 0x09 // UP`. ⚠️ **strapping boot-mode** ESP32-C3: tenuto premuto al reset, con GPIO8 alto → Joint Download Boot (è la procedura di recovery del README) |
| 10 | SPI **CS** display | "SPI" pin 3 | `CONFIG_LV_DISP_SPI_CS=10` |
| 11–17 | non disponibili | — | riservati alla flash SPI integrata nel modulo |
| 18/19 | USB D-/D+ | USB-C | USB-Serial/JTAG nativo (README) — non usabili come GPIO applicativi |
| 20/21 | UART0 RX/TX | "RS232" pin 3 (RX) / pin 2 (TX) | console seriale di fallback |

Display: **ST7789V**, 2.8", pannello 240×320 ma **pilotato dal firmware come 320×240**
(`CONFIG_LV_HOR_RES_MAX=320`, `CONFIG_LV_VER_RES_MAX=240`) con **`MADCTL = 0xC0`**
(`CONFIG_LV_DISPLAY_ORIENTATION=0`, chiamato `PORTRAIT` nel driver → `{0xC0,0x00,0x60,0xA0}[0]`
in `st7789.c`), 16 bit/pixel (`COLMOD 0x55`), **senza inversione colori** (`CONFIG_LV_INVERT_COLORS`
non impostato → `INVOFF`). Quindi la rotazione 0 di Tasmota è un raster **320 di larghezza ×
240 di altezza** con MADCTL `C0`: è ciò che fissa la riga `:H` del `display.ini` più sotto.

Backlight: **non è su un GPIO** dell'ESP32-C3 (`CONFIG_LV_ENABLE_BACKLIGHT_CONTROL` non
impostato). È pilotata dai 4 pin `P1_0..P1_3` dell'AW9523B in modalità LED a corrente costante,
registri DIM `0x20..0x23` (`set_screen_led_backlight()` in `led.c`). Gli altri 12 pin
dell'AW9523B (`P0_0..P0_7`, `P1_4..P1_7`) escono sui connettori `RGB0..RGB3`.

Alimentazione (solo hardware analogico, nessun GPIO da configurare): carica LiPo TP4054,
protezione DW01, step-up MT3608 (5 V per i WS2812), step-down MT3410LB oppure LDO RT9080
(3,3 V logica, selezionabili via resistenze 0 Ω).

Connettori fisici (8): `SPI`, `I2C`, `RGB0`, `RGB1`, `RGB2`, `RGB3`, `RS232`, `POW`.

## Quale binario Tasmota — il punto critico è il display

- Il binario precompilato **`tasmota32c3.bin` non contiene nessun driver display**: nella tabella
  ufficiale delle build `USE_DISPLAY` / `USE_UNIVERSAL_DISPLAY` sono presenti solo nelle varianti
  `-display` e `-lvgl`, e queste **esistono solo per ESP32 classico** (`tasmota32-display.bin`,
  `tasmota32-lvgl.bin`). Su `ota.tasmota.com` per il C3 ci sono solo `tasmota32c3.bin`,
  `tasmota32c3.factory.bin` e `tasmota32c3ser-safeboot.bin`. **Per usare il display serve una
  build personalizzata** (vedi *Build custom* più sotto). Nella cartella *unofficial* di
  `github.com/tasmota/install` (branch `firmware`) esiste `tasmota32c3-lvgl.factory.bin`, che
  include uDisplay ma è compilato `USE_DISPLAY_LVGL_ONLY`: niente `DisplayText`, schermo
  pilotabile solo da Berry/LVGL e pesante su un C3 senza PSRAM. Piano B, non piano A.
- Con il binario stock funzionano comunque: Wi-Fi/MQTT/web UI, i **7 WS2812**, i **due pulsanti**,
  il bus **I2C** (`I2CScan`) e **Berry** (quindi anche backlight/AW9523 via script).
- I driver display specifici per TFT SPI (fra cui l'ST7789 legacy, `DisplayModel 12`) **sono
  stati rimossi** dal sorgente Tasmota (in v15.6.0 non esiste più `xdsp_12_ST7789.ino`): resta
  solo lo **Universal Display Driver** (`DisplayModel 17`, descrittore `display.ini`). La
  configurazione sotto usa quello.
- Console: nelle release attuali `tasmota32c3.bin` usa la **console USB (HWCDC)** sul
  connettore USB-C con fallback su UART0 (GPIO20/21, connettore "RS232") quando l'USB non è
  collegato; la vecchia variante separata `tasmota32c3cdc` non è più pubblicata.

## Cosa è supportato **nativamente** da Tasmota

| Hardware | Componente Tasmota | Richiede | Come si abilita |
|---|---|---|---|
| 7 LED WS2812 frontali | Light (`Pixels`, `Color`, `Scheme`, `Fade`, `Dimmer`) | binario stock | Template: `WS2812` (1376) su GPIO5, poi `Pixels 7` |
| Button1 / Button2 (DOWN / UP) | `Button` | binario stock | Template: `Button1` (32) su GPIO8, `Button2` (33) su GPIO9. Con un solo dispositivo (la Light WS2812) **entrambi commutano `Power1`**: per distinguerli serve `SetOption73 1` + una regola, vedi *Pulsanti* |
| Bus I2C | `I2CScan`, accesso da Berry | binario stock | Template: `I2C SCL` (608) su GPIO0, `I2C SDA` (640) su GPIO1 |
| Display ST7789 (320×240 in rotazione 0) | Universal Display Driver (`DisplayModel 17`) + `display.ini` | **build custom** con `USE_DISPLAY` + `USE_UNIVERSAL_DISPLAY` | Template: `SPI CLK/MOSI/CS/DC` + `Display Rst` + `Option A3`; comandi `DisplayText`, `DisplayRotate`, ecc. |

## Cosa **non** è supportato nativamente

- **AW9523B** (I/O expander + driver LED a corrente costante): nessun driver Tasmota. Quindi
  **backlight del display** e **connettori RGB0–RGB3** non sono raggiungibili con i comandi
  standard (`Backlight`, `Dimmer` del display, `Power` su expander…). Alla partenza il chip resta
  nello stato di reset (tutti i pin in modalità GPIO, non LED): finché uno script non lo
  programma via I2C la retroilluminazione non è sotto controllo → il display può risultare
  **buio anche se Tasmota lo sta pilotando correttamente**.
- **TSC2007** (touch resistivo I2C): nessun driver. Il touch universale di Tasmota (uTouch)
  supporta XPT2046 (SPI), FT5206/FT6336, GT911, CST816S (I2C), non il TSC2007. Il firmware
  ufficiale del badge non lo usa nemmeno lui.
- **Radar/BLE** (ricerca badge vicini), **giochi**, **sync schedule**, **animazioni rainbow**,
  **web UI del badge**: logica applicativa, non replicabile con Tasmota stock.
- **Driver I2C "fantasma"** (verificato sul badge RHC22, stesso chip allo stesso indirizzo): il
  driver MLX90614 (indice 32, indirizzo `0x5A`) scambia l'AW9523B per un termometro a infrarossi
  e riempie la console di `mlx checksum error`. Disabilitarlo con `I2CDriver32 0` (impostazione
  persistente). Allo stesso indirizzo rispondono anche i driver CCS811 (indice 24, `0x5A/0x5B`)
  e MPR121 (indice 23, `0x5A..0x5D`): se la build li include e compaiono, `I2CDriver24 0` /
  `I2CDriver23 0`. Indici nella pagina *I2CDEVICES* della documentazione.

## Cosa è raggiungibile tramite **scripting Berry**

Berry è incluso in `tasmota32c3.bin`. L'accesso I2C **non** passa da un modulo `i2c`: si usano
gli oggetti `tasmota.wire1` / `tasmota.wire2` (bus 1 = i pin `I2C SCL/SDA` del template) oppure
`tasmota.wire_scan(addr)`, che cerca il chip sui bus configurati e restituisce il `wire` giusto o
`nil`. Metodi: `wire.write(addr, reg, val, size)`, `wire.read(addr, reg, size)`,
`wire.write_bytes(addr, reg, bytes)`, `wire.read_bytes(addr, reg, size)`, `wire.scan()`,
`wire.detect(addr)`. Un driver si registra con `tasmota.add_driver(istanza)`, un comando console
con `tasmota.add_cmd(nome, funzione)`. Gli script vanno nel filesystem (LittleFS) e si caricano
da `autoexec.be`.

### Backlight e connettori RGB* via AW9523B

Registri rilevanti dell'AW9523B (stessi valori scritti da `led_init()` in `led.c`):

| Registro | Significato | Valore del firmware | Nota |
|---|---|---|---|
| `0x11` | GCR: limite corrente LED (ISEL) e modo push-pull P0 | `0x01` | **non** è il "LED mode" |
| `0x12` | LED mode switch porta P0 (bit=0 → LED, bit=1 → GPIO; reset = `0xFF`) | `0x80` | P0_0..P0_6 LED, P0_7 GPIO |
| `0x13` | LED mode switch porta P1 | `0x80` | P1_0..P1_6 LED (include la backlight P1_0..P1_3), P1_7 GPIO |
| `0x20..0x23` | DIM P1_0..P1_3 → **backlight** | 0..255 | |
| `0x24..0x2B` | DIM P0_0..P0_7 → `RGB0`, `RGB1`, `RGB2` (pin 2-3) | | |
| `0x2C..0x2F` | DIM P1_4..P1_7 → `RGB2` (pin 4), `RGB3` | | |

Senza le scritture su `0x12`/`0x13` i registri DIM non hanno alcun effetto (pin in modalità
GPIO). Script **non testato sull'hardware**, ma allineato riga per riga a `led.c`:

```berry
# aw9523_backlight.be — backlight display via AW9523B (0x5A), stessi registri di main/badge/led.c
class AW9523_Backlight
  var wire, addr
  def init(addr)
    self.addr = addr
    self.wire = tasmota.wire_scan(addr)      # cerca il chip sui bus I2C configurati
    if self.wire == nil
      print(format("AW9523: chip 0x%02X non trovato", addr))
      return
    end
    self.wire.write(addr, 0x11, 0x01, 1)     # GCR (limite di corrente), come led_init()
    self.wire.write(addr, 0x12, 0x80, 1)     # P0_0..P0_6 in LED mode
    self.wire.write(addr, 0x13, 0x80, 1)     # P1_0..P1_6 in LED mode -> abilita i 4 pin backlight
  end
  def set(level)                             # 0..255, equivale a set_screen_led_backlight()
    if self.wire == nil return end
    for reg: [0x20, 0x21, 0x22, 0x23]        # DIM di P1_0..P1_3
      self.wire.write(self.addr, reg, level, 1)
    end
  end
end

var bl = AW9523_Backlight(0x5A)
bl.set(180)

# comando console/MQTT: AwBacklight 0..255
tasmota.add_cmd('AwBacklight', def (cmd, idx, payload)
  bl.set(int(payload))
  tasmota.resp_cmnd_done()
end)
```

Per i connettori `RGB*` si usano i registri DIM `0x24..0x2F`, ma **solo i pin in modalità LED
rispondono al DIM**. I valori `0x80` dello script riproducono `led_init()` e bastano per la
backlight, ma lasciano due canali dei connettori in modalità GPIO:

| Pin AW9523B | Connettore | Registro DIM | Registro di modalità |
|---|---|---|---|
| `P0_7` | `RGB2`, pin 3 | `0x2B` | `0x12`, bit 7 |
| `P1_7` | `RGB3`, pin 4 | `0x2F` | `0x13`, bit 7 |

Per usare **tutti i 16 pin come uscite LED** (4 backlight + 12 connettori) sostituire le due
scritture su `0x12`/`0x13` in `init()` con `0x00`. Se alcuni pin servono come GPIO, mantenere a 1
i rispettivi bit in `0x12`/`0x13` e usare i registri `0x02`/`0x03` (output) e `0x04`/`0x05`
(direzione). (Integrato dalla PR #1.)

### Touch TSC2007

Protocollo: si invia un byte di comando e si leggono 2 byte (12 bit, MSB first). Comandi di
misura: `0xC0` = X, `0xD0` = Y, `0xE0` = Z1, `0xF0` = Z2. Abbozzo (**non testato**; l'indirizzo
dipende dai pin A0/A1 del chip, `0x48..0x4B`: verificarlo con `I2CScan`):

```berry
var tw = tasmota.wire_scan(0x48)
if tw != nil
  var bx = tw.read_bytes(0x48, 0xC0, 2)
  var by = tw.read_bytes(0x48, 0xD0, 2)
  var x = (bx[0] << 4) | (bx[1] >> 4)
  var y = (by[0] << 4) | (by[1] >> 4)
  print(format("touch x=%d y=%d", x, y))
end
```

## Configurazione Tasmota

Codici componente **Tasmota32/ESP32** (pagina *Components*, tabella ESP32 — quelli della tabella
ESP8266 sono diversi per i componenti display): `I2C SCL1=608`, `I2C SDA1=640`, `SPI MISO1=672`,
`SPI MOSI1=704`, `SPI CLK1=736`, `SPI CS1=768`, `SPI DC1=800`, `Display Rst=1024`, `WS2812=1376`,
`Button1=32`, `Button2=33`, `Option A3=6210`.

Per ESP32-C3 l'array `GPIO` del template ha **22 elementi**, indice = numero GPIO (0…21);
gli indici 11–17 (flash) restano a 0 (stesso schema del template ufficiale "SuperMini ESP32-C3").

### Template (Universal Display Driver)

```json
{"NAME":"WHY2025-EMF2026 Badge","GPIO":[608,640,6210,1024,800,1376,736,704,32,33,768,0,0,0,0,0,0,0,0,0,0,0],"FLAG":0,"BASE":1}
```

Indice per indice: 0 `I2C SCL`, 1 `I2C SDA`, 2 `Option A3`, 3 `Display Rst`, 4 `SPI DC`,
5 `WS2812`, 6 `SPI CLK`, 7 `SPI MOSI`, 8 `Button1`, 9 `Button2`, 10 `SPI CS`.

`Option A3` è il **marcatore virtuale** che attiva lo Universal Display Driver: va messo su un
GPIO "libero" e non configura fisicamente il pin. Su questo badge tutti i GPIO 0–10 sono
occupati; GPIO2 (MISO) è il candidato naturale perché uDisplay scrive soltanto verso il display e
non usa MISO. Alternativa, se si vuole tenere `SPI MISO` (672) su GPIO2: `Option A3` su GPIO18
(pin USB, anch'esso virtuale).

### `display.ini` (da caricare nel filesystem: *Consoles → Manage File system*)

**Verificato sul badge.** Copia pronta nel repo: [`tasmota/display.ini`](tasmota/display.ini).
Descrittore uDisplay ricavato dalla sequenza di init di `st7789.c` del firmware ufficiale
(stessi comandi e parametri; `36,1,C0` = orientamento del badge; `20,0` = `INVOFF`); la riga `:H`
dichiara **320×240**, le dimensioni LVGL del firmware. Formato `:I`: `comando, numero argomenti
(hex), argomenti…`; il nibble alto del contatore aggiunge una pausa (`8x` = 150 ms).

```ini
:H,ST7789,320,240,16,SPI,1,*,*,*,*,*,*,*,40
:S,2,1,1,0,40,20
:I
CF,3,00,83,30
ED,4,64,03,12,81
E8,3,85,01,79
CB,5,39,2C,00,34,02
F7,1,20
EA,2,00,00
C0,1,26
C1,1,11
C5,2,35,3E
C7,1,BE
36,1,C0
3A,1,55
20,0
B1,2,00,1B
F2,1,08
26,1,01
E0,0E,D0,00,02,07,0A,28,32,44,42,06,0E,12,14,17
E1,0E,D0,00,02,07,0A,28,31,54,47,0E,1C,17,1B,1E
2A,4,00,00,00,EF
2B,4,00,00,01,3F
B7,1,07
B6,4,0A,82,27,00
11,80
29,80
:o,28
:O,29
:A,2A,2B,2C
:R,36
:0,C0,00,00,00
:1,A0,00,00,01
:2,00,00,00,02
:3,60,00,00,03
:i,20,21
#
```

Gli `*` nella riga `:H` prendono i pin dal template (`SPI CS`, `SPI CLK`, `SPI MOSI`, `SPI DC`,
`Backlight` → non assegnato, `Display Rst`, `SPI MISO` → non assegnato). `40` = 40 MHz: se
l'immagine è corrotta provare `20`. Le righe `:0..:3` sono le 4 rotazioni di `DisplayRotate 0..3`
(0°, 90° orario, 180°, 270°, tabella `C0/A0/00/60`): `:0` è l'orientamento del firmware
(320×240), `:1`/`:3` danno 240×320; se rosso e blu risultano scambiati aggiungere `0x08` (BGR)
ai quattro valori MADCTL.

### Risoluzione e orientamento

Le dimensioni in `:H` descrivono il raster **nella rotazione 0** e devono corrispondere a ciò che
il pannello indirizza con il MADCTL della riga `:0`. Su questo badge il riferimento è il firmware
ufficiale: LVGL a **320×240** con `MADCTL 0xC0`. Quindi:

- `:H,ST7789,320,240,…` + `:0,C0,…` = rotazione 0 identica al firmware (**configurazione
  verificata sul badge**);
- `DisplayRotate 1` o `3` → uDisplay passa a 240×320 e usa i MADCTL con bit `MV` (`A0`, `60`);
  `DisplayRotate 2` = 320×240 capovolto (`00`);
- **sbagliato**: `:H,ST7789,240,320,…` con `C0` (la prima versione di questa guida). uDisplay
  limita x a 239 mentre il pannello ne indirizza 320: la fascia **destra** dello schermo (80
  colonne) non viene mai disegnata né aggiornata. È il sintomo osservato sul badge.

Controlli rapidi dopo ogni modifica al file (serve `Restart 1`):

```
Display
DisplayText [B63488z]
DisplayText [B0z][x10y10s2]Test
```

`Display` riporta `Model 17`, `Width 320`, `Height 240` e `Rotate` effettivi; `[B63488z]` riempie
di rosso **tutta** l'area logica (se resta una fascia nera, il file caricato non è questo);
`[B0z]` torna al nero. Non partire dall'esempio `ST7789_display.ini` di Tasmota: è per pannelli
240×240 con offset `50` (80 px) nelle rotazioni.

Per la dimensione del testo non si tocca la risoluzione: `DisplaySize 1..4` oppure `[sN]` dentro
`DisplayText`; `DisplayFont` per i font alternativi.

### Comandi di setup (console)

```
Backlog Template {"NAME":"WHY2025-EMF2026 Badge","GPIO":[608,640,6210,1024,800,1376,736,704,32,33,768,0,0,0,0,0,0,0,0,0,0,0],"FLAG":0,"BASE":1}; Module 0
```

Dopo il riavvio, caricare `display.ini` (e gli script Berry + `autoexec.be`) nel filesystem, poi:

```
Backlog DisplayModel 17; DisplayMode 0; DisplayRotate 0; Pixels 7; SetOption73 1; SetOption1 1; SetOption32 10; I2CDriver32 0
Restart 1
DisplayText [z][x20y20s2]Ciao dal badge
I2CScan
```

`Pixels 7` dichiara i 7 WS2812 come Light. `I2CScan` deve mostrare `0x5A` (AW9523B) e, se
alimentato, il TSC2007 (`0x48` tipico). `DisplayModel` deve rispondere `17`: se risponde
"Unknown command" la build non contiene il display.

### Pulsanti

Tasmota associa `Button<n>` a `Power<n>`; qui l'unico dispositivo è la Light WS2812, quindi
**entrambi i pulsanti finiscono a commutare `Power1`** (comportamento osservato sul badge).
`SetOption73 1` li scollega dai relè: a ogni pressione Tasmota pubblica su MQTT
`{"Button<x>":{"Action":"SINGLE"}}` (azioni `SINGLE`/`DOUBLE`/`TRIPLE`/`QUAD`/`PENTA`/`HOLD`) ma
**il trigger per le regole è `Button<x>#State`** con valori numerici: `10` = singola, `11` =
doppia, `12` = tripla, `3` = tenuto (doc *Rules*, esempio `ON button1#state=10 DO …`). Un
trigger `Button<x>#Action=SINGLE` **non scatta**. `SetOption1 1` evita che pressioni multiple
entrino in WifiConfig/Reset; `SetOption32 10` porta il tempo di "tenuto" da 4 s a 1 s.

```
Backlog SetOption73 1; SetOption1 1; SetOption32 10
Rule1 ON Button2#State=10 DO Dimmer + ENDON ON Button1#State=10 DO Dimmer - ENDON ON Button2#State=3 DO Power TOGGLE ENDON ON Button1#State=11 DO Scheme + ENDON
Rule1 1
```

**Verificato sul badge.** UP = più luce, DOWN = meno luce, UP tenuto = LED on/off, DOWN doppio =
animazione successiva. La pressione singola viene riportata con circa mezzo secondo di ritardo
(Tasmota attende
un'eventuale seconda pressione). Con `SetOption73 1` i pulsanti non toccano più `Power` da soli,
quindi l'on/off deve passare dalla regola (o da Berry:
`tasmota.add_rule("Button2#State=3", def () tasmota.cmd("Power TOGGLE") end)`).

**Inserire i comandi uno per riga** nella console e leggere la risposta di ciascuno: il campo
di input è a riga singola, un blocco incollato su più righe viene fuso in una sola (il `Backlog`
viene eseguito e la riga `Rule1 ON …` va persa). Dopo `Rule1 ON …` Tasmota deve rispondere con
`"Length"` > 0 e il testo in `"Rules"`; se risponde `"Length":0,"Rules":""` (caso osservato sul
badge) la regola non è stata ricevuta: reinviare la riga da sola. Poi `Rule1 1` → `"State":"ON"`.
Altri controlli: `SetOption73` deve rispondere `ON`; premendo un tasto in console deve comparire
`{"Button2":{"Action":"SINGLE"}}`; se `Rule1` risponde "Unknown command" la build non include
`USE_RULES`. Alternativa senza regole, in `autoexec.be` (Berry c'è sempre):

```berry
tasmota.add_rule("Button2#State=10", def () tasmota.cmd("Dimmer +") end)
tasmota.add_rule("Button1#State=10", def () tasmota.cmd("Dimmer -") end)
tasmota.add_rule("Button2#State=3", def () tasmota.cmd("Power TOGGLE") end)
tasmota.add_rule("Button1#State=11", def () tasmota.cmd("Scheme +") end)
```

`autoexec.be` minimo:

```berry
load("aw9523_backlight.be")
```

### Build custom (necessaria per il display)

**Via TasmoCompiler** (strada verificata sul badge, nessuna toolchain locale):

```
docker run --rm --name tasmocompiler -p 3000:3000 benzino77/tasmocompiler
```

poi su `http://localhost:3000`: board **ESP32-C3**, versione *release*; nelle *Features* spuntare
`USE_DISPLAY` e `USE_UNIVERSAL_DISPLAY` (più `USE_DISPLAY_MODES1TO5` se servono i DisplayMode
1–5); `USE_I2C`/`USE_SPI` sono inclusi di default; **non** spuntare `USE_LVGL` né
`USE_DISPLAY_LVGL_ONLY`. Nessun *Custom parameter* obbligatorio. In output si ottengono
`firmware.factory.bin` (immagine completa, per il primo flash via cavo) e `firmware.bin`
(immagine OTA, per gli aggiornamenti dal web UI), oltre a `platformio_override.ini` e
`user_config_override.h` generati.

**Via PlatformIO** (equivalente): clonare Tasmota, creare `tasmota/user_config_override.h` dal
file `.sample` con

```c
#define USE_DISPLAY
#define USE_UNIVERSAL_DISPLAY
#define USE_DISPLAY_MODES1TO5   // opzionale
```

e `pio run -e tasmota32c3` → `build_output/firmware/tasmota32c3.factory.bin` e
`tasmota32c3.bin`. Sono le stesse opzioni che `-DFIRMWARE_DISPLAYS` attiva nella variante
`tasmota32-display` per ESP32 classico.

### Flash

Primo flash (immagine *factory*, da offset `0x0`) con esptool:

```
esptool.py --chip esp32c3 --port /dev/ttyACM0 write_flash 0x0 firmware.factory.bin
```

Sul badge la stessa immagine scritta con un web flasher da browser ha prodotto un **boot loop**,
mentre con esptool funziona: usare esptool (con `--erase-all` la prima volta, se il dubbio è lo
stato precedente della flash). Se la porta non entra da sola in download mode: tenere premuto il
centro della rotella **sinistra** (GPIO9), collegare l'USB-C, premere e rilasciare **RST**,
attendere ~2 s e rilasciare (procedura del README).

Aggiornamenti successivi: **OTA dal web UI** (*Firmware Upgrade → Upload file* con
`firmware.bin`), senza cavo e conservando template, Wi-Fi e filesystem (`display.ini`, script
Berry).

### Driver legacy `DisplayModel 12`: non più disponibile

In Tasmota v15.6.0 i driver display specifici per TFT SPI (`xdsp_12_ST7789`, `xdsp_04_ili9341`,
…) **non esistono più** nel sorgente: `#define USE_DISPLAY_ST7789` non abilita nulla e i
componenti `ST7789 CS/DC` del template restano senza driver. L'unica strada è lo Universal
Display Driver descritto sopra.

### Verifiche consigliate

- Controllare da GUI (*Configurazione → Configura template*) che gli indici 2, 4, 10 risultino
  `Option A3`, `SPI DC`, `SPI CS` e non componenti ESP8266 (codici diversi).
- Prima del display, verificare con `I2CScan` che l'AW9523B risponda a `0x5A`, poi che lo script
  Berry accenda la backlight: senza di essa lo schermo resta nero anche se `DisplayText` funziona.
- GPIO9 come pulsante è sicuro (stesso schema del firmware ufficiale). Lo strapping viene
  campionato al reset, prima che Tasmota parta: il livello alto lo garantisce l'hardware del
  badge, non il pull-up software del componente `Button`. Per il download mode servono GPIO9
  basso **e GPIO8 alto**: tenere premuta solo la rotella sinistra, non entrambe.
