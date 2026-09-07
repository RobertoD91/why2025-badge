# Tasmota su WHY2025 / EMF2026 Badge

Questo documento descrive come far girare **Tasmota** (in alternativa al firmware ESP-IDF/LVGL
ufficiale di questo repo) sul badge WHY2025 / EMF2026, riusando tutto l'hardware presente sul
PCB. Le informazioni sui GPIO sono state estratte direttamente dal firmware ufficiale
(`main/badge/led.h`, `main/badge/ui.h`, `sdkconfig.emf2026-badge`) e dal `README.md`, non
supposte.

> **Attenzione concettuale**: questa è una board custom da conferenza (MCU ESP32-C3 + display +
> LED + I2C expander), non un dispositivo "smart plug/switch" tipico di Tasmota. Flashare Tasmota
> **sostituisce interamente** il firmware ufficiale: radar BLE, giochi (Snake, Space Invaders),
> sync schedule via Wi-Fi, animazioni rainbow, ecc. andranno persi. Tasmota può però pilotare
> nativamente display, LED indirizzabili, bus I2C e pulsanti.

## Hardware e mappa GPIO (ESP32-C3)

| GPIO | Funzione sul PCB | Connettore | Note |
|---|---|---|---|
| 0 | I2C **SCL** | "I2C" | bus verso AW9523B (driver LED/backlight) e TSC2007 (touch) |
| 1 | I2C **SDA** | "I2C" | idem |
| 2 | SPI **MISO** display | "SPI" | ST7789 |
| 3 | Display **RESET** | interno | ST7789 |
| 4 | Display **DC** (data/command) | interno | ST7789 |
| 5 | **WS2812** data-out | interno (7 LED frontali) | LED RGB individuali, uscita DOUT anche su pin "1W" del connettore I2C |
| 6 | SPI **CLK** display | "SPI" | ST7789, SPI hardware (FSPI) |
| 7 | SPI **MOSI** display | "SPI" | ST7789 |
| 8 | **Button1** (dial DOWN / switch destro) | "RS232" pin 4 ("button B") | libreria esp32-button, attivo basso, pull-up interno |
| 9 | **Button2** (dial UP / switch sinistro) | "RS232" pin 5 ("button A") | ⚠️ pin di **strapping boot-mode** ESP32-C3 (già usato così anche dal firmware ufficiale: tenuto premuto in boot → Joint Download Boot) |
| 11–17 | non disponibili | — | riservati alla flash SPI integrata nel modulo |
| 18/19 | USB D-/D+ | USB-C | USB-Serial/JTAG nativo, non riassegnabile a funzioni GPIO applicative |
| 20/21 | UART0 RX/TX | "RS232" pin 2/3 | console seriale di default |

Display: **ST7789**, 2.8", 240×320 px, bus SPI **hardware** (HSPI/FSPI) — i pin usati
coincidono esattamente con i pin FSPI di default dell'ESP32-C3.

Alimentazione (solo hardware analogico, nessun GPIO da configurare): carica LiPo TP4054,
protezione DW01, step-up MT3608 (5V per i WS2812), step-down MT3410 / LDO RT9080 (3.3V logica).

Connettori fisici presenti sul PCB (8 totali): `SPI`, `I2C`, `RGB0`, `RGB1`, `RGB2`, `RGB3`
(i 12 pin I/O dell'AW9523B), `RS232`, `POW`.

## Cosa è supportato **nativamente** da Tasmota

| Hardware | Componente Tasmota | Come si abilita |
|---|---|---|
| Display ST7789 240×320 | `DisplayModel 12` (driver `USE_DISPLAY_ST7789`, richiede `USE_SPI`) | via Template GPIO (SPI hardware + `ST7789_CS`/`ST7789_DC`/`Display Rst`) |
| 7 LED WS2812 frontali | Light/`Pixels` | via Template GPIO `WS2812` su GPIO5 |
| Button1 / Button2 (dial UP/DOWN) | `Button` | via Template GPIO `Button1`/`Button2` su GPIO8/GPIO9 |
| Bus I2C (rilevamento) | `I2CScan` | via Template GPIO `I2C_SCL1`/`I2C_SDA1` — mostra gli indirizzi 0x5A/0x5B (AW9523) ma senza driver dedicato non sono pilotabili |

## Cosa **non** è supportato nativamente

- **AW9523B** (I/O expander + driver LED costante, pilota backlight display e connettore
  "RGB*"): nessun driver Tasmota di serie per questo chip (Tasmota supporta altri expander come
  PCA9535/MCP230xx/PCF8574, ma non l'AW9523).
- **TSC2007** (touch resistivo I2C, indirizzo tipico `0x48` da datasheet — il firmware ufficiale
  non lo inizializza nemmeno lui): nessun driver Tasmota nativo (Tasmota supporta touch SPI
  XPT2046, non TSC2007 via I2C).
- **Backlight del display**: essendo pilotata dall'AW9523 via I2C (4 pin) e non da un GPIO
  diretto, il comando standard `Backlight`/dimmer di Tasmota **non si applica** — resterà fissa
  allo stato di default del chip (verosimilmente spenta finché nessuno la accende via I2C).
- **Radar/BLE** (ricerca badge vicini), **giochi** (Snake, Space Invaders), **sync schedule via
  Wi-Fi**, **animazioni rainbow**: logica applicativa del firmware originale, non replicabile con
  Tasmota stock.
- **Connettori "RGB0–RGB3"** (12 I/O extra sull'AW9523): irraggiungibili da Tasmota senza driver
  custom (stesso limite dell'AW9523 sopra).

## Cosa è raggiungibile tramite **scripting Berry**

Il bus I2C è comunque elettricamente disponibile (GPIO0/1) e Berry (il linguaggio di scripting
integrato in Tasmota) espone accesso raw I2C (`i2c.writebytes`/`i2c.readbytes` tramite la classe
`I2C`/`Wire` di Berry) e può registrare un driver custom con `tasmota.add_driver(...)`. Con questo
è **tecnicamente possibile** scrivere un driver Berry per:

- pilotare backlight e connettore RGB* via **AW9523B** (registri LED mode/GPIO mode, PWM 0x20–0x23
  per la backlight, come fa `led.c` del firmware ufficiale — indirizzi 0x5A/0x5B, stessi registri
  già documentati nel codice sorgente di questo repo);
- leggere coordinate touch dal **TSC2007** (comandi di conversione via I2C secondo datasheet).

Non è incluso di serie in Tasmota: va scritto e mantenuto come script `.be` caricato sul
filesystem del dispositivo. Scheletro minimo per la backlight AW9523 (**non testato**, solo punto
di partenza):

```berry
import i2c

class AW9523_Backlight
  var wire, addr
  def init(bus, addr)
    self.wire = i2c.wire(bus)
    self.addr = addr
    self.wire.write(self.addr, 0x11, 0x03, 1)  # LED mode sui pin 0x20-0x23
  end
  def set(level)  # level 0-255
    for reg: [0x20, 0x21, 0x22, 0x23]
      self.wire.write(self.addr, reg, level, 1)
    end
  end
end

aw9523 = AW9523_Backlight(0, 0x5A)
aw9523.set(180)
```

## Configurazione Tasmota

Codici GPIO Tasmota usati (documentazione ufficiale): `I2C_SCL1=608`, `I2C_SDA1=640`,
`SPI_MISO1=672`, `SPI_MOSI1=704`, `SPI_CLK1=736`, `ST7789_CS=6112`, `ST7789_DC=6144`,
`Display_Rst=1024`, `WS2812=1376`, `Button1=32`, `Button2=33`. Per ESP32-C3 l'array `GPIO` del
template ha 22 elementi, uno per ciascun GPIO0…GPIO21 in ordine diretto.

### Template

```json
{"NAME":"WHY2025-EMF2026 Badge","GPIO":[608,640,672,1024,6144,1376,736,704,32,33,6112,0,0,0,0,0,0,0,0,0,0,0],"FLAG":0,"BASE":1}
```

### Comandi di setup (console, dopo aver flashato `tasmota32c3.bin`)

```
Backlog Template {"NAME":"WHY2025-EMF2026 Badge","GPIO":[608,640,672,1024,6144,1376,736,704,32,33,6112,0,0,0,0,0,0,0,0,0,0,0],"FLAG":0,"BASE":1}; Module 0
DisplayModel 12
DisplayMode 0
Pixels 7
I2CScan
```

`Pixels 7` dichiara i 7 LED WS2812 come dispositivo Light (comandi `Color`, `Scheme`, `Fade`,
`Power`). `DisplayModel 12` attiva il driver ST7789: verificare l'inquadratura con
`DisplayText` — il driver Tasmota per ST7789 è pensato soprattutto per pannelli piccoli/quadrati,
quindi su un pannello 240×320 potrebbe servire `DisplayRotate` per centrare correttamente
l'immagine.

### Verifiche consigliate prima del flash definitivo

- Confermare che la build Tasmota32 in uso includa `USE_DISPLAY_ST7789` e `USE_WS2812`
  (nella maggior parte delle build `tasmota32c3.bin` precompilate sono già inclusi; se si
  compila da sorgente, abilitarli in `user_config_override.h`).
- Ricontrollare l'assegnazione GPIO anche da GUI (Configurazione → Configura template) per
  conferma visiva prima di salvare.
- GPIO9 come pulsante è sicuro (stesso schema già usato dal firmware ufficiale): a boot resta
  normalmente alto grazie al pull-up interno che Tasmota applica di default sui `Button`.
