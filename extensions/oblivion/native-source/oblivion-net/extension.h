// SPDX-License-Identifier: GPL-3.0-or-later
#include "smsdk_ext.h"
#include "eiface.h"

class OblivionNetwork final : public SDKExtension
{
public:
    bool SDK_OnMetamodLoad(ISmmAPI *, char *, size_t, bool) override;
    bool SDK_OnLoad(char *, size_t, bool) override;
    void SDK_OnUnload() override;
    void CheckTransmitPost(CCheckTransmitInfo *, const unsigned short *, int);
};
