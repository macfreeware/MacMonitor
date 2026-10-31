# ⚡ MacMonitor

macOS için geliştirilmiş; **sistem loglarını asla şişirmeyen**, **aşırı düşük kaynak tüketen (panel kapalıyken 2 sn aralıkla ~%0,3 CPU, ~40 MB RAM)**, menü çubuğunda (status bar) canlı CPU ve RAM yükünü gösteren, disk boşluğunu da izleyen, tıklandığında modern ve detaylı bir bilgi paneli açan native Swift/SwiftUI durum çubuğu uygulaması.

---

## 📸 Ekran Görüntüleri

**Menü çubuğu:** açık ve koyu menü çubuğuna uyum sağlar; eşik aşılınca değer kırmızıya döner.

<img src="docs/screenshots/menubar.png" width="380" alt="Menü çubuğunda MacMonitor göstergesi, açık ve koyu görünüm">

<table>
<tr>
<td align="center" valign="top"><img src="docs/screenshots/overview.png" width="300" alt="Genel Bakış sekmesi"><br><sub>Genel Bakış: CPU, çekirdekler ve bellek</sub></td>
<td align="center" valign="top"><img src="docs/screenshots/overview-dark.png" width="300" alt="Genel Bakış sekmesi, koyu görünüm"><br><sub>Koyu görünüm</sub></td>
</tr>
<tr>
<td align="center" valign="top"><img src="docs/screenshots/processes.png" width="300" alt="İşlemler sekmesi"><br><sub>İşlemler: en çok CPU / RAM kullananlar</sub></td>
<td align="center" valign="top"><img src="docs/screenshots/disk.png" width="300" alt="Disk sekmesi"><br><sub>Disk: boş ve kullanılan alan</sub></td>
</tr>
</table>

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
- **Disk Boşluğu (Disk sekmesi):**
  - Bağlı her disk (başlangıç diski, harici diskler, USB bellekler) için boş, kullanılan ve toplam alan
  - Doluluğa göre renklenen çubuk (%75'e kadar yeşil, %90'a kadar turuncu, üstü kırmızı)
  - Değerler Finder ile aynı hesaplanır (ondalık GB, silinebilir alan dahil); karta çift tıklayınca disk Finder'da açılır
  - Yalnızca sekme açıkken 5 saniyede bir okunur
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

## 📥 İndir ve Kur

macOS 13 veya üstü gerekir. Apple Silicon ve Intel Mac'lerde çalışır (universal).

[![MacMonitor'ı indir](docs/download-button-tr.png)](https://gitlab.com/freeware2/macmonitor/-/releases/permalink/latest/downloads/MacMonitor.pkg)

1. [Son sürümün](https://gitlab.com/freeware2/macmonitor/-/releases) `MacMonitor-<sürüm>.pkg` dosyasını indirip çift tıklayın.
2. Paket Apple onayından geçmediği için macOS ilk açılışta engeller: uyarıyı **Bitti** ile kapatın, sonra **Sistem Ayarları → Gizlilik ve Güvenlik**'te **Yine de Aç**'a tıklayın.
3. Kurulum adımlarını tamamlayın. MacMonitor menü çubuğunda açılır.

Kurulum paketi istemezseniz `MacMonitor-<sürüm>.zip` dosyasını indirip `MacMonitor.app`'i **Uygulamalar** klasörüne sürükleyin.

## 🛠️ Kaynaktan Derleme

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
│   │   ├── DiskInfo.swift           # Bağlı disklerin boş/toplam alanı
│   │   └── AppSettings.swift        # UserDefaults destekli kullanıcı ayarları
│   ├── Views/
│   │   ├── PopoverContentView.swift # Ana detay penceresi ve sekme yöneticisi
│   │   ├── CPUDetailView.swift      # CPU göstergesi, çekirdek çubukları ve grafik
│   │   ├── MemoryDetailView.swift   # RAM dağılımı, segment barı ve swap
│   │   ├── ProcessListView.swift    # Top CPU / Top RAM süreç listesi
│   │   ├── DiskView.swift           # Disk sekmesi
│   │   ├── SettingsView.swift       # Kullanıcı ayar paneli
│   │   └── SparklineView.swift      # Donanım ivmeli mini trend grafiği
│   └── Helpers/
│       ├── SystemInfoHelper.swift   # Çip modeli, bellek boyutu ve uptime yardımcıları
│       └── LaunchAtLoginHelper.swift# macOS 13+ SMAppService başlatma yardımcısı
├── Resources/
│   ├── Info.plist                   # LSUIElement = true tanımlı plist
│   └── AppIcon.icns                 # Özel macOS uygulama simgesi
├── build.sh                         # Universal (arm64 + x86_64) derleme; --zip ile dağıtım paketi
├── scripts/build_pkg.sh             # Kurulum paketi (.pkg) üretimi
├── install.sh                       # Tek tıkla yükleme ve başlatma betiği
└── Makefile                         # Standart make hedefleri (build, run, install, clean)
```

---

## 🔒 İzinler ve Güvenlik
- Ekstra üçüncü parti kütüphane ya da internet bağımlılığı içermez.
- `root` (sudo) yetkisi gerektirmez.
- Gizliliğinizi korur; dışarıya hiçbir veri göndermez (ağ erişimi yoktur).

## 📄 Lisans

Copyright © 2026 Rafet SAPANCI

MacMonitor özgür yazılımdır: [GNU Genel Kamu Lisansı](LICENSE) sürüm 3 ya da (tercihinize göre) sonraki bir sürümün koşullarıyla kullanabilir, değiştirebilir ve dağıtabilirsiniz (GPL-3.0-or-later). Program **hiçbir garanti olmadan** sunulur.
