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