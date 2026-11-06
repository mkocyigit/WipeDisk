<div align="center">

<img src="Resources/AppIcon-preview.png" width="128" alt="WipeDisk">

# WipeDisk

macOS icin ham disk silme araci — SwiftUI arayuz, ayricalikli yardimci islem, canli ilerleme.

</div>

---

> [!WARNING]
> **Bu arac verileri kalici olarak yok eder.** Uzerine yazilan bir disk kurtarilamaz.
> Diski silmeden once mutlaka **Deneme modu** ile calistirin ve aygit tanimlayicisini
> (`diskN`) iki kez kontrol edin.
>
> Yazilim **"OLDUGU GIBI"**, hicbir garanti olmadan sunulur. Kullanimindan dogan
> **her turlu veri kaybi ve zarardan kullanici sorumludur** — bkz.
> [Sorumluluk reddi](#sorumluluk-reddi).

## Ne yapar

Secilen tam diskin uzerine, secilen desende bastan sona yazar. Dosyalari silmez —
bolum tablosu dahil butun ham blok aygitini uzerine yazar.

- **Silme yontemleri:** tek gecis sifir, tek gecis rastgele, DoD 5220.22-M (7 gecis), Gutmann (35 gecis)
- **Dogrulama:** son gecisten sonra disk geri okunup yazilanla karsilastirilir
- **Deneme modu:** butun akis calisir, diske tek bayt gitmez
- **Silme sonrasi bicimlendirme:** ExFAT, APFS, HFS+, FAT32, NTFS
- **Canli ilerleme:** gecis bazinda yuzde, hiz, gecen ve kalan sure
- **Durdurulabilir:** islem sirasinda durdurma istegi gonderilebilir

## Bicimlendirme

**Bicimlendir** sekmesi diskin tamamini tek adimda tek birim yapar: dosya sistemi,
sema ve birim adi secilir, gerisini `diskutil eraseDisk` halleder. Gunluk kullanimda
istenen sey genelde budur.

Bicimlendirme veriyi **uzerine yazmaz** — yalnizca bolum tablosunu ve dosya sistemini
yeniler. Veriyi kurtarilamaz kilmak icin **Sil** sekmesi gerekir. Onay penceresi
bunu acikca soyler.

## Bolumleme

**Bolumle** sekmesi diski birden fazla bolume ayirir:

- Bolum sayisi, her bolume ayri dosya sistemi, ad ve boyut
- GPT veya MBR semasi
- Bicimlendirilmeden birakilacak **bos alan** bolumleri
- Planin disk uzerindeki dagilimini gosteren canli oran seridi
- **Tek birim bicimlendirme:** bolum tablosuna dokunmadan yalnizca secili birimi
  yeniden bicimlendirir

Plan uygulanmadan once diske gore dogrulanir; engelleyici sorunlar dugmeyi kapatir,
uyarilar (or. cok buyuk FAT32) gosterilir ama devam etmeye izin verir:

| Kontrol | Davranis |
|---|---|
| MBR'de dortten fazla bolum | Engeller |
| MBR uzerinde APFS | Engeller |
| Toplam boyut diskten buyuk | Engeller |
| "Kalan alan" son bolumde degil | Engeller |
| Butun bolumler bos alan | Engeller |
| FAT32 32 GB'in uzerinde | Uyarir |

Bu islemler ham aygita yazmaz; `diskutil`e devredilir. `diskutil` Apple tarafindan
imzali oldugundan **bolumleme ve bicimlendirme Tam Disk Erisimi izni istemez** —
bu izin yalnizca silme icin gereklidir. Bolumleme `diskutil`e devredildigi icin
yarida kesilemez, bu yuzden durdurma dugmesi gosterilmez.

## Guvenlik onlemleri

Yanlis diski silmek tek tikla olacak bir sey olmamali. Bu yuzden:

- **Sistem diski listede kilitli.** Acilis birimi sentezlenmis bir APFS kabinin icinde
  oldugundan, kap → fiziksel depo zinciri sabit noktaya kadar geriye izlenir ve zincirdeki
  butun tam diskler kara listeye alinir.
- **Sanal aygitlar engellenir.** Disk imajlari ve sentezlenmis APFS kaplari silinemez;
  sentezlenmis kaplarda hangi fiziksel deponun silinmesi gerektigi soylenir.
- **Aygit tanimlayicisi elle yazilir.** Onay penceresinde `diskN` degerini yazmadan
  silme dugmesi acilmaz — refleksle "Tamam"a basmaya karsi kasitli bir surtunme.
- **Yardimci islem arayuze guvenmez.** Silmeden hemen once diski `diskutil`den
  yeniden okur, korumali olup olmadigini kendi basina dogrular.
- **`--device` ve `--confirm` birebir eslesmelidir.**

## Kurulum

macOS 14+ ve Xcode komut satiri araclari gerekir.

```sh
git clone https://github.com/mkocyigit/WipeDisk.git
cd WipeDisk
Scripts/make-app.sh --install   # derler ve /Applications altina kurar
open /Applications/WipeDisk.app
```

Kurmadan denemek icin `Scripts/make-app.sh` yeterli; paket `build/WipeDisk.app`
altinda kalir. Diger secenekler: `--universal` (arm64 + x86_64), `--debug`, `--open`.

`--install` calisan ornegi kapatir, `/Applications` altina kopyalar ve kurulan
paketin imzasini dogrular. `/Applications` yonetici kullanicilar icin yazilabilir
oldugundan normalde `sudo` gerekmez.

### Tam Disk Erisimi gerekiyor

macOS, ham disk aygitlarina (`/dev/rdiskN`) erisimi **root olsa bile** TCC izniyle
kapatir. Yonetici parolasi bu izni vermez. Ilk calistirmadan once:

1. **Sistem Ayarlari › Gizlilik ve Guvenlik › Tam Disk Erisimi**
2. Listeye `build/WipeDisk.app` ekleyin, anahtari acin
3. Uygulamayi tamamen kapatip yeniden acin

Izin verilmemisse uygulama `errno 1` yerine bunu acikca soyler ve ilgili ayar
panelini acan bir dugme gosterir.

> Paket ad-hoc imzalandigi icin **her yeniden derlemede** imza ozeti degisir ve
> Tam Disk Erisimi kaydi duser. Yeniden derledikten sonra izni tekrar vermeniz gerekir.

## Komut satiri

Arayuz olmadan da kullanilabilir:

```sh
# Diskleri JSON olarak listele (root gerekmez)
build/WipeDisk.app/Contents/MacOS/wipe-helper --list

# Deneme calistirmasi — hicbir sey yazmaz
sudo wipe-helper --device disk6 --confirm disk6 --method zeros --dry-run

# Gercek silme: 7 gecis DoD, sonrasinda dogrula ve ExFAT olarak bicimlendir
sudo wipe-helper --device disk6 --confirm disk6 --method dod7 \
                 --verify --reformat exfat --label YEDEK

# Tek bir birimi yeniden bicimlendir (bolum tablosuna dokunmaz)
sudo wipe-helper --erase-volume disk6s2 --confirm disk6s2 --format exfat --label DATA

# Diskin tamamini bicimlendir
sudo wipe-helper --erase-disk disk6 --confirm disk6 --format exfat --scheme gpt --label YEDEK

# JSON plandan bolumle
sudo wipe-helper --partition plan.json --confirm disk6
```

Bolumleme plani `PartitionPlan` yapisinin JSON karsiligidir:

```json
{
  "device": "disk6",
  "scheme": "GPT",
  "partitions": [
    { "id": "…", "name": "BOOT", "format": "fat32", "size": { "bytes": { "_0": 1000000000 } } },
    { "id": "…", "name": "DATA", "format": "exfat", "size": { "remainder": {} } }
  ]
}
```

`--help` butun secenekleri listeler.

## NTFS ve diger dosya sistemleri

| Dosya sistemi | Okuma | Yazma | Bicimlendirme |
|---|---|---|---|
| APFS, HFS+, ExFAT, FAT32 | ✅ | ✅ | ✅ |
| NTFS | ✅ salt okunur | ❌ (FSKit modulu gelistiriliyor) | ✅ `mkntfs` ile |
| ReFS | ❌ | ❌ | ❌ |

macOS, NTFS birimlerini **yerlesik olarak salt okunur baglar** — ek surucu gerekmez.
macOS 26'da bu, cekirdek eklentisi yerine kullanici alaninda calisan bir surucudur
(`ntfs.fs`, `FSImplementation = UserFS`). Uygulama birimin gercek dosya sistemini
gosterir ve NTFS birimlerini **Salt okunur** rozetiyle isaretler.

Bir birim bagli degilse (or. silme denemesi diski ayirdiysa) satirdaki **Bagla**
dugmesi geri baglar. Baglama ve ayirma yonetici yetkisi istemez.

macOS NTFS bicimlendiricisi icermez (`diskutil listFilesystems` ciktisinda NTFS
yoktur). Bu bosluk ntfs-3g projesinin `mkntfs` araciyla kapatilir:
`Scripts/build-ntfsprogs.sh` araci kaynaktan derler (SHA-256 dogrulamasiyla),
`Scripts/make-app.sh` uygulama paketine koyar. NTFS'e **yazmak** icin asagidaki
FSKit modulu gerekir.
ReFS icin macOS'ta hicbir surucu yoktur — okuma bile mumkun degildir.

## NTFS yazma (FSKit modulu) — gelistirme asamasinda

`Sources/NTFSFSModule/`, macOS'un salt okunur NTFS'ini asmak icin bir FSKit
dosya sistemi modulu. Yaklasim, NTFS'i sifirdan yazmak degil: okuma-yazma
destegi olgun olan **libntfs-3g**'yi FSKit'in cagri yuzeyine baglamak.

Onemli tasarim karari: sandbox'li bir uzanti `/dev/diskNsM`'i dogrudan acamaz.
libntfs-3g'nin takilabilir `ntfs_device_operations` katmani kullanilarak
kutuphanenin butun G/C'si FSKit'in `FSBlockDeviceResource`'una yonlendiriliyor;
boylece aygit acma yetkisi hic gerekmiyor.

Uygulanan protokoller (20 metot):

| Protokol | Kapsam |
|---|---|
| `FSVolume.Operations` | baglama, oznitelikler, arama, dizin listeleme, olusturma, silme, yeniden adlandirma, sabit bag |
| `FSVolume.ReadWriteOperations` | `$DATA` ozniteligi uzerinden okuma ve yazma |
| `FSVolume.OpenCloseOperations` | yazma kipi denetimi, kapanista senkronizasyon |

### Calistirmak icin gereken

Modul `com.apple.developer.fskit.fsmodule` yetkisi olmadan **yuklenmez**. Bu,
Apple'in kendi exfat modulunun de kullandigi, ucuncu taraflara acik bir yetki;
ama gecerli olmasi icin ucretli bir gelistirici hesabina bagli provisioning
profile ile imzalanmasi gerekir. Ad-hoc imza bu yetkiyi tasiyamaz.

```sh
SIGN_IDENTITY="Developer ID Application: Adiniz (TEAMID)" Scripts/make-app.sh --install
```

Olculen durum: ad-hoc imzayla paket sisteme **kaydoluyor** (`pluginkit -m -p
com.apple.fskit.fsmodule` ciktisinda Apple'in modulleriyle yan yana gorunuyor),
fakat bir NTFS birimi baglandiginda macOS yine kendi salt okunur surucusunu
kullaniyor ve modulumuze hic basvurmuyor.

> [!WARNING]
> Bu modulun hicbir yolu henuz calistirilmadi — yalnizca derleniyor. Yetki
> alindiktan sonra her metot once **atilabilir bir disk imaji** uzerinde
> sinanmali. Test edilmemis bir NTFS yazicisi veriyi sessizce bozar.

## Mimari

```
Sources/
├── CDiskIO/      Ham disk ioctl'leri icin C kopru katmani
│                 (Swift, C variadic fonksiyonlarini dogrudan cagiramaz)
├── WipeKit/      Disk listeleme + silme motoru — arayuz ve yardimci ortak kullanir
│   ├── DiskEnumerator   diskutil ciktisini okur, korumali diskleri belirler
│   ├── WipeEngine       ham aygita desen yazar, dogrular, ilerleme yayinlar
│   ├── PartitionPlan    bolumleme plani, dogrulamasi ve diskutil katmani
│   ├── WipeMethod       gecis desenleri
│   └── WipeEvent        iki surec arasindaki JSON satir protokolu
├── wipe-helper/  root olarak calisan, asil yazma islemini yapan CLI
└── WipeDisk/     Ayricaliksiz SwiftUI arayuz
```

Arayuz **hicbir zaman root calismaz.** Silme istendiginde `wipe-helper`i
`osascript … with administrator privileges` ile arka planda baslatir; iki surec
paylasilan bir dosya uzerinden JSON satirlariyla haberlesir. Durdurma istegi,
onceden anlasilan bir yolda dosya olusturularak bildirilir ve her parcada bakilir.

## Ikon

`Scripts/make-icon.swift` ikonu tamamen Core Graphics ile cizer — disaridan hicbir
gorsel varlik kullanilmaz, dolayisiyla telif kisiti yoktur.

```sh
swift Scripts/make-icon.swift Resources
```

## Sorumluluk reddi

Bu yazilimi kullanarak asagidaki kosullari kabul etmis olursunuz:

1. **Garanti yoktur.** Yazilim "OLDUGU GIBI" sunulur; calisacagina, hatasiz
   olacagina, belirli bir amaca uygun olacagina veya verileri guvenli bicimde
   silecegine dair acik ya da ortulu hicbir garanti verilmez.
2. **Sorumluluk tamamen kullanicidadir.** Yazilimin kullanimi, yanlis kullanimi
   veya kullanilamamasi sonucu olusan veri kaybi, donanim hasari, is kaybi ya da
   dogrudan veya dolayli herhangi bir zarardan yazarlar ve katkida bulunanlar
   **hicbir kosulda sorumlu tutulamaz.**
3. **Silme geri alinamaz.** Silme, bicimlendirme ve bolumleme islemleri verileri
   kalici olarak yok edebilir. Dogru diski secmek, yedek almak ve islemi onaylamak
   kullanicinin sorumlulugundadir.
4. **Guvenli silme garantisi verilmez.** SSD'lerde asinma dengeleme (wear leveling),
   ayrilmis alanlar ve denetleyici davranisi nedeniyle uzerine yazma, verilerin
   adli yontemlerle kurtarilamayacagini garanti etmez. Yasal veya kurumsal imha
   gereksinimleri icin sertifikali yontemler kullanin.
5. **Deneysel bilesenler.** NTFS FSKit modulu test edilmemistir ve verileri
   bozabilir; yalnizca atilabilir disklerde denenmelidir.
6. **Ucuncu taraf yazilim.** ntfs-3g gibi ucuncu taraf bilesenler kendi
   lisanslarina tabidir ve onlarin davranisi icin de sorumluluk kabul edilmez.

Bu kosullar, [LICENSE](LICENSE) dosyasindaki MIT lisansinin garanti ve
sorumluluk reddi hukumlerini tamamlar; celiski halinde lisans metni gecerlidir.

## Lisans

WipeDisk'in kaynak kodu **MIT lisansi** altindadir — bkz. [LICENSE](LICENSE).
Kodu ticari amacla dahil ozgurce kullanabilir, degistirebilir ve
dagitabilirsiniz. Tek sart: **telif bildirimi ve lisans metni, kodun tum
kopyalarinda korunmalidir.** Yazilim garantisiz sunulur ve yazarlar hicbir
zarardan sorumlu degildir.

**Istisna — ntfs-3g:** NTFS ozellikleri, GPL-2.0-or-later lisansli
[ntfs-3g](https://github.com/tuxera/ntfs-3g) projesinin `mkntfs` aracini ve
`libntfs-3g` kutuphanesini kullanir. Bu ikililer depoda tutulmaz;
`Scripts/build-ntfsprogs.sh` ile kaynaktan derlenir. libntfs-3g'ye baglanan
**NTFS FSKit modulu derlenip dagitildiginda, o ikili GPL kosullarina tabidir**
(MIT, GPL ile uyumlu oldugundan bu mumkundur). Uygulama paketi ntfs-3g lisans
metinlerini `Contents/Resources/Licenses/` altinda tasir.
