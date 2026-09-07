# Tasmota su WHY2025 / EMF2026 Badge

Questo documento descrive come far girare **Tasmota** (in alternativa al firmware ESP-IDF/LVGL
ufficiale di questo repo) sul badge WHY2025 / EMF2026, riusando tutto l'hardware presente sul
PCB. Le informazioni sui GPIO e sui registri sono estratte dal firmware ufficiale
(`main/badge/led.c`, `main/badge/led.h`, `main/badge/ui.h`, `sdkconfig.emf2026-badge`,
`components/lvgl_esp32_drivers/lvgl_tft/st7789.c`) e dal `README.md`; i codici componente e il
comportamento di Tasmota dalla documentazione ufficiale (pagine *Components*, *Displays*,
*Universal Display Driver*, *Berry*, *BUILDS*) e dai binari pubblicati su `ota.tasmota.com`.

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
| 8 | **Button1** = DOWN (rotella destra / pressione centrale destra) | "RS232" pin 4 o 5 | `ui.h`: `BUTTON_1 0x08 // DOWN`; attivo basso, pull-up interno. Il README chiama i due segnali "button A/B" ma non dice quale sia quale |
| 9 | **Button2** = UP (rotella sinistra / pressione centrale sinistra) | "RS232" pin 4 o 5 | `ui.h`: `BUTTON_2 0x09 // UP`. ⚠️ **strapping boot-mode** ESP32-C3: tenuto premuto al reset → Joint Download Boot (è la procedura di recovery del README) |
| 10 | SPI **CS** display | "SPI" pin 3 | `CONFIG_LV_DISP_SPI_CS=10` |
| 11–17 | non disponibili | — | riservati alla flash SPI integrata nel modulo |
| 18/19 | USB D-/D+ | USB-C | USB-Serial/JTAG nativo (README) — non usabili come GPIO applicativi |
| 20/21 | UART0 RX/TX | "RS232" pin 3 (RX) / pin 2 (TX) | console seriale di fallback |

Display: **ST7789V**, 2.8", **240×320**, SPI hardware a 16 bit/pixel (`COLMOD 0x55`). Il firmware
ufficiale lo usa in **portrait con `MADCTL = 0xC0`** (`CONFIG_LV_DISPLAY_ORIENTATION=0` →
`{0xC0,0x00,0x60,0xA0}[0]` in `st7789.c`) e **senza inversione colori** (`CONFIG_LV_INVERT_COLORS`
non impostato → `INVOFF`). Questi due dettagli servono per il `display.ini` più sotto.

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
  build personalizzata** (vedi *Build custom* più sotto).
- Con il binario stock funzionano comunque: Wi-Fi/MQTT/web UI, i **7 WS2812**, i **due pulsanti**,
  il bus **I2C** (`I2CScan`) e **Berry** (quindi anche backlight/AW9523 via script).
- Tasmota sta dismettendo i driver display specifici (fra cui l'ST7789 legacy, `DisplayModel 12`)
  in favore dello **Universal Display Driver** (`DisplayModel 17`, descrittore `display.ini`).
  La configurazione sotto usa quello.
- Console: nelle release attuali `tasmota32c3.bin` usa la **console USB (HWCDC)** sul
  connettore USB-C con fallback su UART0 (GPIO20/21, connettore "RS232") quando l'USB non è
  collegato; la vecchia variante separata `tasmota32c3cdc` non è più pubblicata.

## Cosa è supportato **nativamente** da Tasmota

| Hardware | Componente Tasmota | Richiede | Come si abilita |
|---|---|---|---|
| 7 LED WS2812 frontali | Light (`Pixels`, `Color`, `Scheme`, `Fade`, `Dimmer`) | binario stock | Template: `WS2812` (1376) su GPIO5, poi `Pixels 7` |
| Button1 / Button2 (DOWN / UP) | `Button` | binario stock | Template: `Button1` (32) su GPIO8, `Button2` (33) su GPIO9; consigliato `SetOption73 1` (eventi `Button1#Action` invece di comandare un relè che non esiste) |
| Bus I2C | `I2CScan`, accesso da Berry | binario stock | Template: `I2C SCL` (608) su GPIO0, `I2C SDA` (640) su GPIO1 |
| Display ST7789 240×320 | Universal Display Driver (`DisplayModel 17`) + `display.ini` | **build custom** con `USE_DISPLAY` + `USE_UNIVERSAL_DISPLAY` | Template: `SPI CLK/MOSI/CS/DC` + `Display Rst` + `Option A3`; comandi `DisplayText`, `DisplayRotate`, ecc. |

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
- Attenzione: alcuni driver sensore inclusi in `tasmota32` condividono gli indirizzi
  `0x5A`/`0x5B` (es. CCS811, MLX90614). Se dopo il boot compare un sensore "fantasma" a quegli
  indirizzi, disabilitare il driver corrispondente con `I2CDriver<n> 0` (indici nella pagina
  *I2CDEVICES* della documentazione).

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

Per i connettori `RGB*` basta scrivere gli altri registri DIM (`0x24..0x2F`) con la stessa
`wire.write`; se servono come GPIO invece che come LED, impostare a 1 il bit corrispondente in
`0x12`/`0x13` e usare i registri `0x02`/`0x03` (output) e `0x04`/`0x05` (direzione).

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
`Button1=32`, `Button2=33`, `Option A3=6210` (legacy: `ST7789 CS=6592`, `ST7789 DC=6624`).

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

Descrittore uDisplay ricavato dalla sequenza di init di `st7789.c` del firmware ufficiale
(stessi comandi e parametri; `36,1,C0` = portrait del badge; `20,0` = `INVOFF`). Formato `:I`:
`comando, numero argomenti (hex), argomenti…`; il nibble alto del contatore aggiunge una pausa
(`8x` = 150 ms).

```ini
:H,ST7789,240,320,16,SPI,1,*,*,*,*,*,*,*,40
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
:1,60,00,00,01
:2,00,00,00,02
:3,A0,00,00,03
:i,20,21
#
```

Gli `*` nella riga `:H` prendono i pin dal template (`SPI CS`, `SPI CLK`, `SPI MOSI`, `SPI DC`,
`Backlight` → non assegnato, `Display Rst`, `SPI MISO` → non assegnato). `40` = 40 MHz: se
l'immagine è corrotta provare `20`. Le righe `:0..:3` sono le 4 rotazioni (`DisplayRotate 0..3`),
con `:0` uguale all'orientamento del firmware ufficiale; se rosso e blu risultano scambiati
aggiungere `0x08` (BGR) ai quattro valori MADCTL.

### Comandi di setup (console)

```
Backlog Template {"NAME":"WHY2025-EMF2026 Badge","GPIO":[608,640,6210,1024,800,1376,736,704,32,33,768,0,0,0,0,0,0,0,0,0,0,0],"FLAG":0,"BASE":1}; Module 0
```

Dopo il riavvio, caricare `display.ini` (e gli script Berry + `autoexec.be`) nel filesystem, poi:

```
Backlog DisplayModel 17; DisplayMode 0; DisplayRotate 0; Pixels 7; SetOption73 1
Restart 1
DisplayText [z][x20y20]Ciao dal badge
I2CScan
```

`Pixels 7` dichiara i 7 WS2812 come Light; `SetOption73 1` scollega i pulsanti dai relè e
pubblica `{"Button1":{"Action":"SINGLE"}}` (usabile in regole: `ON Button1#Action=SINGLE DO …`, o
in Berry con `tasmota.add_rule`). `I2CScan` deve mostrare `0x5A` (AW9523B) e, se alimentato,
il TSC2007 (`0x48` tipico).

`autoexec.be` minimo:

```berry
load("aw9523_backlight.be")
```

### Build custom (necessaria per il display)

1. Clonare Tasmota, creare `tasmota/user_config_override.h` dal file `.sample` e aggiungere:

   ```c
   #define USE_DISPLAY
   #define USE_UNIVERSAL_DISPLAY
   #define USE_DISPLAY_MODES1TO5   // opzionale, per DisplayMode 1..5
   ```

   Sono le stesse opzioni che il flag `-DFIRMWARE_DISPLAYS` attiva nella variante
   `tasmota32-display` per ESP32 classico.
2. `pio run -e tasmota32c3` → in `build_output/firmware/` si ottengono
   `tasmota32c3.factory.bin` (flash completo da `0x0`) e `tasmota32c3.bin` (OTA).
3. Alternativa senza toolchain: Gitpod/TasmoCompiler online selezionando target ESP32-C3 e le
   feature display, se esposte.

### Flash

```
esptool.py --chip esp32c3 --port /dev/ttyACM0 write_flash 0x0 tasmota32c3.factory.bin
```

Se la porta non entra da sola in download mode: tenere premuto il centro della rotella
**sinistra** (GPIO9), collegare l'USB-C, premere e rilasciare **RST**, attendere ~2 s e rilasciare
(procedura del README).

### Alternativa legacy (sconsigliata): driver `DisplayModel 12`

Compilando con `#define USE_DISPLAY_ST7789` al posto di `USE_UNIVERSAL_DISPLAY`, il template usa i
componenti dedicati (`ST7789 CS=6592` su GPIO10, `ST7789 DC=6624` su GPIO4, `SPI MISO=672` su
GPIO2, niente `Option A3`):

```json
{"NAME":"WHY2025-EMF2026 Badge (legacy)","GPIO":[608,640,672,1024,6624,1376,736,704,32,33,6592,0,0,0,0,0,0,0,0,0,0,0],"FLAG":0,"BASE":1}
```

Il driver legacy nasce per pannelli 240×240 e Tasmota lo sta rimuovendo: verificare
`DisplayWidth`/`DisplayHeight`/`DisplayRotate` e preferire comunque uDisplay.

### Verifiche consigliate

- Controllare da GUI (*Configurazione → Configura template*) che gli indici 2, 4, 10 risultino
  `Option A3`, `SPI DC`, `SPI CS` e non componenti ESP8266 (codici diversi).
- Prima del display, verificare con `I2CScan` che l'AW9523B risponda a `0x5A`, poi che lo script
  Berry accenda la backlight: senza di essa lo schermo resta nero anche se `DisplayText` funziona.
- GPIO9 come pulsante è sicuro (stesso schema del firmware ufficiale): Tasmota applica il
  pull-up sui `Button`, quindi al boot il pin resta alto se non lo si tiene premuto.
