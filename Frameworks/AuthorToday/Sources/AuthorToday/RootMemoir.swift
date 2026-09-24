//
//  Copyright © 2026 Alexander Babaev.
//  Licensed under the MIT License. See LICENSE in the repository root.
//

import Memoirs

/// Where everything this package logs goes: os_log, under a category per tracer label.
let rootMemoir: Memoir = OSLogMemoir(subsystem: "com.lonelybytes.authortoday", isSensitive: false)
