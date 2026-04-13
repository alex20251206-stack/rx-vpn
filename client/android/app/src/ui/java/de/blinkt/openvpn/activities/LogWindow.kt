/*
 * Copyright (c) 2012-2016 Arne Schwabe
 * Distributed under the GNU GPL v2 with additional terms. For full terms see the file doc/LICENSE.txt
 */
package de.blinkt.openvpn.activities

import android.content.Intent
import android.os.Bundle
import androidx.activity.OnBackPressedCallback
import com.ruoxue.vpn.R
import de.blinkt.openvpn.fragments.LogFragment

/**
 * Created by arne on 13.10.13.setUpEdgeEdgeStuff
 */
class LogWindow : BaseActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.log_window)
        supportActionBar?.setDisplayHomeAsUpEnabled(true)

        onBackPressedDispatcher.addCallback(
            this,
            object : OnBackPressedCallback(true) {
                override fun handleOnBackPressed() {
                    navigateToSubscriptionHome()
                }
            }
        )

        if (savedInstanceState == null) {
            supportFragmentManager.beginTransaction()
                .add(R.id.container, LogFragment())
                .commit()
        }

        setUpEdgeEdgeInsetsListener(getWindow().getDecorView().getRootView(), R.id.container)
    }

    private fun navigateToSubscriptionHome() {
        startActivity(
            Intent(this, RxSubscriptionActivity::class.java).addFlags(
                Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            )
        )
        finish()
    }

    override fun onSupportNavigateUp(): Boolean {
        navigateToSubscriptionHome()
        return true
    }
}
