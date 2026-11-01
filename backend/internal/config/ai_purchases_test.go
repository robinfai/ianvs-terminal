package config

import "testing"

func TestApplePurchaseConfiguration(t *testing.T) {
	valid := ApplePurchases{BundleID: "work.ianvs.trail", IssuerID: "issuer", KeyID: "key", PrivateKeyFile: "/private/key.p8", Environment: "Production", Products: map[string]int64{"pack": 497500}}
	if err := valid.Validate(); err != nil {
		t.Fatal(err)
	}
	if valid.Products["pack"]*2000*2 != 1990000000 {
		t.Fatal("US$1.99 pack must be twice its model cost")
	}
	for _, test := range []func(*ApplePurchases){
		func(p *ApplePurchases) { p.Environment = "Xcode" },
		func(p *ApplePurchases) { p.PrivateKeyFile = "" },
		func(p *ApplePurchases) { p.Products = map[string]int64{"pack": 0} },
		func(p *ApplePurchases) { p.Products = map[string]int64{"pack": 1000000001} },
		func(p *ApplePurchases) { p.Products = nil },
	} {
		p := valid
		test(&p)
		if p.Validate() == nil {
			t.Fatal("invalid purchase config accepted")
		}
	}
}
