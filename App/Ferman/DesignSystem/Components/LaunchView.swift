import SwiftUI

/// AçılışEkranı (G15) — mürekkep zemin üstünde kelime markası, `HomeView`'in kendi kelime markasıyla
/// aynı yazı ve harf aralığı. Kısa bir marka anıdır; içerik yüklemesi bunu beklemez (`ContentView`
/// senkronik olarak zaten yüklemiştir), o yüzden burada tutulacak bir durum yok.
struct LaunchView: View {
    var body: some View {
        Text(verbatim: "FERMAN")
            .font(.custom("Archivo-SemiBold", size: 40, relativeTo: .largeTitle))
            .tracking(10)
            .foregroundStyle(Color.paper)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.ink)
            .accessibilityHidden(true)
    }
}

#Preview("LaunchView") {
    LaunchView()
}
