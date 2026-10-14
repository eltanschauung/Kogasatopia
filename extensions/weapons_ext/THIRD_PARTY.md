# Weapons services provenance

Native engine code is maintained by Hombre in `weapons_ext`; each port retains
its upstream authorship. No old library aliases or forwarding plugins are
provided for the services merged here.

| Service | Reference implementation |
| --- | --- |
| Attributes | FlaminSarge, [TF2Attributes v1.7.5](https://github.com/FlaminSarge/tf2attributes/tree/v1.7.5) |
| Utilities | nosoop, [TF2 Utils 1.4.0](https://github.com/nosoop/SM-TFUtils/tree/1.4.0), GPL-3.0 |
| Damage forwards | nosoop, [SM-TFOnTakeDamage 1.3.3](https://github.com/nosoop/SM-TFOnTakeDamage/tree/1.3.3), GPL-3.0 |
| Dynamic attribute configuration and native injector | nosoop, [SMExt-TFEconDynamic](https://github.com/nosoop/SMExt-TFEconDynamic), GPL-3.0 with SourceMod linking exception; port includes name-index fix from local revision `fcd588f` |
| FOV preferences | Andrew Betson, [TF-FOV](https://github.com/AndrewBetson/TF-FOV), AGPL-3.0-or-later |
| Projectile centering | rtldg and pufftwitt, [v8.0](https://github.com/rtldg/tf2centerprojectiles/tree/v8.0) |
| Bunnyhop caller migration | Mikusch, [tf-bhop 1.9.0](https://github.com/Mikusch/tf-bhop/tree/1.9.0), GPL-3.0; only API include/call changed |

Projectile-centering notice: Copyright 2020, rtldg. Copying and distribution,
with or without modification, are permitted in any medium without royalty,
provided the copyright notice and this notice are preserved. Offered as-is,
without any warranty.

The FOV SourcePawn preference module retains its AGPL license; the independently
implemented native FOV integration is GPL-3.0-or-later. The complete linked
SourcePawn plugin must be distributed consistently with the component licenses.
The corresponding license text is retained alongside the sources.

The pre-existing component notices in this extension still apply.
