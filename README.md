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

## Ne yapar

Secilen tam diskin uzerine, secilen desende bastan sona yazar. Dosyalari silmez —
bolum tablosu dahil butun ham blok aygitini uzerine yazar.

- **Silme yontemleri:** tek gecis sifir, tek gecis rastgele, DoD 5220.22-M (7 gecis), Gutmann (35 gecis)
- **Dogrulama:** son gecisten sonra disk geri okunup yazilanla karsilastirilir
- **Deneme modu:** butun akis calisir, diske tek bayt gitmez
- **Silme sonrasi bicimlendirme:** ExFAT, APFS, HFS+, FAT32
- **Canli ilerleme:** gecis bazinda yuzde, hiz, gecen ve kalan sure
- **Durdurulabilir:** islem sirasinda durdurma istegi gonderilebilir

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
git clone https://github.com/KULLANICI/WipeDisk.git
cd WipeDisk
Scripts/make-app.sh          # build/WipeDisk.app uretir
open build/WipeDisk.app
```

Secenekler: `--universal` (arm64 + x86_64), `--debug`, `--open`.

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
```

`--help` butun secenekleri listeler.

## Mimari

```
Sources/
├── CDiskIO/      Ham disk ioctl'leri icin C kopru katmani
│                 (Swift, C variadic fonksiyonlarini dogrudan cagiramaz)
├── WipeKit/      Disk listeleme + silme motoru — arayuz ve yardimci ortak kullanir
│   ├── DiskEnumerator   diskutil ciktisini okur, korumali diskleri belirler
│   ├── WipeEngine       ham aygita desen yazar, dogrular, ilerleme yayinlar
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
