local tests = WoWUnit("AzerothLedgerSmoke")

-- Confirms that a passing assertion is reported by WoWUnit.
function tests.DeliberatePass(_self)
    WoWUnit.AreEqual(2, 1 + 1)
end

-- Confirms that a failing assertion is reported by WoWUnit.
function tests.DeliberateFailure(_self)
    WoWUnit.AreEqual(2, 1)
end
