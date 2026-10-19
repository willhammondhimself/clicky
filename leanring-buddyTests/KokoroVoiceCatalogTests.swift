import Testing

#if canImport(leanring_buddy)
@testable import leanring_buddy
#else
@testable import LumenLogic
#endif

struct KokoroVoiceCatalogTests {

    @Test func defaultVoiceIsBritishMaleGeorge() {
        #expect(KokoroVoiceCatalog.defaultVoice == "bm_george")
        #expect(KokoroVoiceCatalog.voiceCodes.contains("bm_george"))
    }

    @Test func labelsDescribeAccentAndGender() {
        #expect(KokoroVoiceCatalog.label(forVoiceCode: "bm_george") == "George (British, male)")
        #expect(KokoroVoiceCatalog.label(forVoiceCode: "af_heart") == "Heart (American, female)")
        #expect(KokoroVoiceCatalog.label(forVoiceCode: "bf_isabella") == "Isabella (British, female)")
    }

    @Test func labelFallsBackToRawCodeForUnknownVoice() {
        #expect(KokoroVoiceCatalog.label(forVoiceCode: "zz_mystery") == "zz_mystery")
        #expect(KokoroVoiceCatalog.label(forVoiceCode: "") == "")
    }

    @Test func availableVoicesListsBritishBeforeAmericanAlphabetically() {
        let voices = KokoroVoiceCatalog.availableVoices()
        #expect(voices.count == 28)
        #expect(voices.first?.id == "bf_alice")
        let firstAmericanIndex = voices.firstIndex { $0.id.hasPrefix("a") }
        let lastBritishIndex = voices.lastIndex { $0.id.hasPrefix("b") }
        #expect(firstAmericanIndex != nil && lastBritishIndex != nil)
        #expect(lastBritishIndex! < firstAmericanIndex!)
        #expect(voices.contains(KokoroVoiceOption(id: "bm_george", label: "George (British, male)")))
    }

    @Test func availableVoicesOnlyContainsAmericanAndBritishCodes() {
        let voices = KokoroVoiceCatalog.availableVoices()
        #expect(voices.allSatisfy { $0.id.hasPrefix("af_") || $0.id.hasPrefix("am_") || $0.id.hasPrefix("bf_") || $0.id.hasPrefix("bm_") })
    }
}
