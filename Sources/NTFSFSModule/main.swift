import Foundation

// Bu gövde hiç çalışmaz.
//
// Uzantı .appex olarak paketlendiğinde gerçek giriş noktası Foundation'ın
// NSExtensionMain'idir; bağlayıcıya `-e _NSExtensionMain` ile bu söyleniyor
// (Apple'ın kendi FSKit modülleri de aynı sembolü kullanıyor). Yine de SwiftPM
// yürütülebilir hedefler için bir main sembolü ürettiğinden, bağlanabilmesi
// adına burada boş bir dosya bulunuyor.
//
// Uzantı doğrudan çalıştırılırsa yapacak bir iş yok; sessizce çıkılır.
exit(0)
