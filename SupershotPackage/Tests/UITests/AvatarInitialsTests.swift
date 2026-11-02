import Testing
import UI

struct AvatarInitialsTests {
  @Test(arguments: [
    ("North Shore Basketball Club", "NSB"),
    ("The North Shore", "NS"),
    ("THE North Shore", "NS"),
    ("University of the West", "UW"),
    ("North & South", "NS"),
    ("Lakers", "L"),
    ("NBA", "NBA"),
    ("The", "T"),
    ("The Of", "TO"),
    ("THE", "T"),
    ("a an the of and for in on at to North Shore", "NS"),
    ("A An And For In On At To", "AAA"),
    ("Athletic Anderson Forest", "AAF"),
    ("  North\tShore\nBasketball  ", "NSB"),
    ("North-Shore/Basketball.Club", "NSB"),
    ("North&South", "NS"),
    (" nba ", "N"),
    ("Nba", "N"),
    ("WNBA", "WNB"),
    ("AB", "AB"),
    ("123", "1"),
    ("Étoile du Nord", "ÉDN"),
    ("e\u{301}toile North South", "E\u{301}NS"),
    ("東京", "東"),
    ("👩🏽‍🚀 North Shore", "👩🏽‍🚀NS"),
    ("ß North South", "SSN"),
    ("", "?"),
    (" \t\n ", "?"),
    ("...---", "?"),
  ])
  func extractsInitials(name: String, expected: String) {
    let initials = AvatarView.makeInitials(from: name)
    #expect(initials == expected)
    #expect(initials.count <= 3)
  }
}
