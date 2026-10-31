# ⚡ MacMonitor

macOS için geliştirilmiş; **sistem loglarını asla şişirmeyen**, **aşırı düşük kaynak tüketen (panel kapalıyken 2 sn aralıkla ~%0,3 CPU, ~25 MB RAM)**, menü çubuğunda (status bar) canlı CPU ve RAM yükünü gösteren, tıklandığında modern ve detaylı bir bilgi paneli açan native Swift/SwiftUI durum çubuğu uygulaması.

---

## 🌟 Öne Çıkan Özellikler

### 1. 🚀 Sıfır Sistem Logu ve Ultra Düşük Kaynak Tüketimi
- Çoğu araç periyodik olarak `top`, `ps`, `vm_stat` gibi harici kabuk (shell) komutları çağırır. Bu durum macOS teşhis/denetim loglarını binlerce satırla doldurur, her saniye alt süreç (sub-process) başlatıp bataryayı ve işlemciyi tüketir.
- **MacMonitor**, doğrudan **Darwin / Mach Kernel C API'lerini** (`host_statistics64`, `host_processor_info`, `sysctlbyname`) bellek içi sistem çağrılarıyla kullanır.
- Süreç taraması (`proc_listpids` / `proc_pidinfo`) **yalnızca detay penceresi açıkken** çalışır. Pencere kapalıyken süreç taraması anında durdurulur; arka planda mikrosaniye düzeyinde çalışır.

### 2. 🖥️ Menü Çubuğu (Status Bar) Bilgi Alanı
- Menü çubuğunda anlık CPU ve RAM doluluğu görünür.
- Kullanıcı dilediği formatı seçebilir:
  - **Simgeli (Önerilen):** Apple native `cpu` ve `memorychip` donanım sembolleri (`[cpu] 12%  [ram] 48%`)
  - **Metinli:** `CPU 12%  RAM 48%`
  - **Sade:** `12% · 48%`
  - **Sadece CPU:** `[cpu] 12%`
  - **Sadece RAM:** `[ram] 48%`
- **Akıllı Uyarı Sistemi:** CPU veya RAM belirlenen eşiği aştığında (örneğin %85 veya %90), menü çubuğu yazısı otomatik olarak kırmızıya bürünerek sizi uyarır.

### 3. 🔍 Tıklanınca Açılan Detaylı Pencere (Popover)
Menü çubuğundaki göstergeye tıklandığında açılan şık, yarı saydam (translucent macOS materyali) pencere şunları içerir:
- **İşlemci (CPU) Detayları:**
  - Genel kullanım yüzdesi ve durum göstergesi
  - Kullanıcı (User), Sistem (System) ve Boşta (Idle) çekirdek yükü ayrımı
  - **Çekirdek Dağılımı:** Tüm fiziksel ve sanal çekirdeklerin (E-Core / P-Core) ayrı ayrı anlık yük çubukları
  - **Canlı Yük Geçmişi:** Son 60 saniyenin dalgalanmasını gösteren akıcı mini sparkline grafiği
- **Bellek (RAM) Detayları:**
  - Kullanılan ve toplam bellek miktarı (Örn: `6.4 GB / 8.0 GB - %80`)
  - **Segmentli Bellek Dağılımı:**
    - 🟦 Uygulamalar (Active Memory)
    - 🟪 Bağlı Sistem (Wired Memory)
    - 🟧 Sıkıştırılmış Bellek (Compressed)
    - 🟩 Boş / Önbellek (Free & Inactive)
  - Takas Alanı (Swap Memory) kullanımı
  - Canlı RAM doluluk geçmiş grafiği
- **En Çok Kaynak Tüketen İşlemler:**
  - Sekmeler: **En Çok CPU** | **En Çok RAM**
  - İlk 6 işlemin adı, PID numarası ve anlık tüketimi (yalnızca kendi kullanıcınızın işlemleri; sistem işlemleri root yetkisi gerektirir)
  - Doğrudan macOS **Etkinlik Monitörü**'nü açma kısayolu
- **Sistem ve Donanım Bilgisi:**
  - İşlemci çipi modeli (Örn: Apple M2 / Intel Core)
  - Açık kalma süresi (Uptime)

### 4. ⚙️ Kullanıcı Konforu ve Özelleştirme (Ayarlar Sekmesi)
- **Yenileme Sıklığı:** 0,5 sn (Canlı), 1 sn (Hızlı), 2 sn (Önerilen), 3 sn (Hafif), 5 sn (Ultra Eko). Ölçülen boşta yük: 2 sn ~%0,3, 1 sn ~%0,5, 0,5 sn ~%0,9 CPU (tek çekirdek).
- **Menü Çubuğu Görünümü:** Simgeli, Kompakt, Sade, Sadece CPU, Sadece RAM
- **Yüksek Kullanım Uyarıları:**
  - CPU ve RAM uyarı eşikleri: %20 ile %95 arası, 5'er adımla (varsayılan CPU %85, RAM %90)
  - Renkli uyarı vurgusu açma/kapama
- **Mini Geçmiş Grafikleri:** Aç / Kapat
- **Mac Başlangıcında Çalıştır:** Aç / Kapat (`SMAppService` entegrasyonu)
- **Sağ Tık Menüsü:** Menü simgesine sağ tıklandığında hızlı menü açılır (Aç, Yenile, Etkinlik Monitörü, Çıkış).
- **Dock İkonu Yok:** `LSUIElement = true` özelliği sayesinde Dock'ta yer kaplamaz, tam anlamıyla minimalist bir durum çubuğu aracıdır.

---

## 🛠️ Kurulum ve Çalıştırma

Projeyi tek bir komutla derleyip doğrudan `/Applications` (Uygulamalar) klasörünüze yükleyebilir ve başlatabilirsiniz:

```bash
git clone https://gitlab.com/freeware2/macmonitor.git
cd macmonitor
./install.sh
```

veya `make` komutu ile:

```bash
make install
```

Sadece anlık denemek isterseniz:
```bash
./build.sh
open build/MacMonitor.app
```

---

## 📁 Proje Mimarisi

```
MacMonitor/
├── Sources/
│   ├── main.swift                   # @main başlangıç noktası
│   ├── AppDelegate.swift            # NSStatusItem ve NSPopover yönetimi, menü etkileşimleri
│   ├── Models/
│   │   ├── SystemMonitor.swift      # Mach Kernel API ve sysctl sorgu motoru
│   │   ├── CPUInfo.swift            # Çekirdek ve CPU veri modeli
│   │   ├── MemoryInfo.swift         # RAM ve Swap veri modeli
│   │   ├── ProcessInfo.swift        # Süreç listeleme modeli
│   │   └── AppSettings.swift        # UserDefaults destekli kullanıcı ayarları
│   ├── Views/
│   │   ├── PopoverContentView.swift # Ana detay penceresi ve sekme yöneticisi
│   │   ├── CPUDetailView.swift      # CPU göstergesi, çekirdek çubukları ve grafik
│   │   ├── MemoryDetailView.swift   # RAM dağılımı, segment barı ve swap
│   │   ├── ProcessListView.swift    # Top CPU / Top RAM süreç listesi
│   │   ├── SettingsView.swift       # Kullanıcı ayar paneli
│   │   └── SparklineView.swift      # Donanım ivmeli mini trend grafiği
│   └── Helpers/
│       ├── SystemInfoHelper.swift   # Çip modeli, bellek boyutu ve uptime yardımcıları
│       └── LaunchAtLoginHelper.swift# macOS 13+ SMAppService başlatma yardımcısı
├── Resources/
│   ├── Info.plist                   # LSUIElement = true tanımlı plist
│   └── AppIcon.icns                 # Özel macOS uygulama simgesi
├── build.sh                         # Universal (arm64 + x86_64) derleme; --zip ile dağıtım paketi
├── install.sh                       # Tek tıkla yükleme ve başlatma betiği
└── Makefile                         # Standart make hedefleri (build, run, install, clean)
```

---

## 🔒 İzinler ve Güvenlik
- Ekstra üçüncü parti kütüphane ya da internet bağımlılığı içermez.
- `root` (sudo) yetkisi gerektirmez.
- Gizliliğinizi korur; dışarıya hiçbir veri göndermez.

## 📄 Lisans

Copyright © 2026 Rafet SAPANCI

MacMonitor özgür yazılımdır: [GNU Genel Kamu Lisansı](LICENSE) sürüm 3 ya da (tercihinize göre) sonraki bir sürümün koşullarıyla kullanabilir, değiştirebilir ve dağıtabilirsiniz (GPL-3.0-or-later). Program **hiçbir garanti olmadan** sunulur.
