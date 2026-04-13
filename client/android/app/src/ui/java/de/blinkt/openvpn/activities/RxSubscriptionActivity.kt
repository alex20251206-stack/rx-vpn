package de.blinkt.openvpn.activities

import android.content.Intent
import android.net.TrafficStats
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.widget.ArrayAdapter
import android.widget.Button
import android.widget.EditText
import android.widget.ListView
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import de.blinkt.openvpn.LaunchVPN
import com.ruoxue.vpn.R
import de.blinkt.openvpn.VpnProfile
import de.blinkt.openvpn.core.ConfigParser
import de.blinkt.openvpn.core.OpenVPNService
import de.blinkt.openvpn.core.ProfileManager
import java.io.StringReader
import java.net.HttpURLConnection
import java.net.URL
import java.util.UUID
import java.util.regex.Pattern
import kotlin.concurrent.thread

class RxSubscriptionActivity : AppCompatActivity() {
    private lateinit var statusText: TextView
    private lateinit var speedText: TextView
    private lateinit var input: EditText
    private lateinit var listView: ListView
    private lateinit var adapter: ArrayAdapter<String>
    private val subs = mutableListOf<String>()
    private val ui = Handler(Looper.getMainLooper())
    private var lastRx = 0L
    private var lastTx = 0L

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setTitle(R.string.app)
        setContentView(R.layout.activity_rx_subscription)

        statusText = findViewById(R.id.rxStatus)
        speedText = findViewById(R.id.rxSpeed)
        input = findViewById(R.id.rxInputUrl)
        listView = findViewById(R.id.rxSubList)

        adapter = ArrayAdapter(this, android.R.layout.simple_list_item_single_choice, subs)
        listView.choiceMode = ListView.CHOICE_MODE_SINGLE
        listView.adapter = adapter

        findViewById<Button>(R.id.rxSaveSub).setOnClickListener {
            val url = input.text.toString().trim()
            if (url.isEmpty()) return@setOnClickListener
            if (!subs.contains(url)) {
                subs.add(url)
                saveSubs()
                adapter.notifyDataSetChanged()
            }
            val idx = subs.indexOf(url)
            if (idx >= 0) listView.setItemChecked(idx, true)
            statusText.text = getString(R.string.rx_saved)
        }

        findViewById<Button>(R.id.rxDeleteSub).setOnClickListener {
            val pos = listView.checkedItemPosition
            if (pos in subs.indices) {
                subs.removeAt(pos)
                saveSubs()
                adapter.notifyDataSetChanged()
                statusText.text = getString(R.string.rx_deleted)
            }
        }

        findViewById<Button>(R.id.rxConnect).setOnClickListener {
            val pos = listView.checkedItemPosition
            if (pos !in subs.indices) {
                Toast.makeText(this, R.string.rx_select_subscription, Toast.LENGTH_SHORT).show()
                return@setOnClickListener
            }
            val url = subs[pos]
            fetchAndConnect(url)
        }

        findViewById<Button>(R.id.rxOpenLog).setOnClickListener {
            startActivity(Intent(this, LogWindow::class.java))
        }

        loadSubs()
        tickSpeed()
    }

    private fun tickSpeed() {
        lastRx = TrafficStats.getTotalRxBytes()
        lastTx = TrafficStats.getTotalTxBytes()
        ui.post(object : Runnable {
            override fun run() {
                val curRx = TrafficStats.getTotalRxBytes()
                val curTx = TrafficStats.getTotalTxBytes()
                val down = (curRx - lastRx).coerceAtLeast(0L)
                val up = (curTx - lastTx).coerceAtLeast(0L)
                speedText.text = getString(R.string.rx_speed_fmt, fmtSpeed(down), fmtSpeed(up))
                lastRx = curRx
                lastTx = curTx
                ui.postDelayed(this, 1000)
            }
        })
    }

    private fun fmtSpeed(v: Long): String {
        val kb = v / 1024.0
        return if (kb < 1024) String.format("%.1f KB/s", kb) else String.format("%.2f MB/s", kb / 1024.0)
    }

    private fun loadSubs() {
        val prefs = getSharedPreferences("rx_subscriptions", MODE_PRIVATE)
        val joined = prefs.getString("list", "") ?: ""
        subs.clear()
        if (joined.isNotBlank()) subs.addAll(joined.split("\n").map { it.trim() }.filter { it.isNotEmpty() })
        adapter.notifyDataSetChanged()
        if (subs.isNotEmpty()) listView.setItemChecked(0, true)
    }

    private fun saveSubs() {
        getSharedPreferences("rx_subscriptions", MODE_PRIVATE)
            .edit()
            .putString("list", subs.joinToString("\n"))
            .apply()
    }

    private fun fetchAndConnect(subscriptionUrl: String) {
        statusText.text = getString(R.string.rx_downloading)
        thread {
            try {
                val conn = (URL(subscriptionUrl).openConnection() as HttpURLConnection).apply {
                    connectTimeout = 15000
                    readTimeout = 30000
                    requestMethod = "GET"
                    setRequestProperty("Accept", "text/plain")
                }
                val content = conn.inputStream.bufferedReader().use { it.readText() }
                if (!content.contains("<ca>")) error(getString(R.string.rx_invalid_ovpn))
                val parsed = parseProfileForTunnel(content)
                RxTlsTunnel.restart(
                    remoteHost = parsed.remoteHost,
                    remotePort = parsed.remotePort,
                    caPem = parsed.caPem,
                    localPort = parsed.localPort
                )
                val rewritten = rewriteProfileRemote(content, parsed.localPort)

                val parser = ConfigParser()
                parser.parseConfig(StringReader(rewritten))
                val profile: VpnProfile = parser.convertProfile().apply {
                    mName = "RX-${UUID.randomUUID().toString().take(6)}"
                }
                val pm = ProfileManager.getInstance(this)
                pm.addProfile(profile)
                ProfileManager.saveProfile(this, profile)
                pm.saveProfileList(this)

                val start = Intent(this, LaunchVPN::class.java).apply {
                    putExtra(LaunchVPN.EXTRA_KEY, profile.getUUIDString())
                    putExtra(OpenVPNService.EXTRA_START_REASON, "rx-subscription-connect")
                    action = Intent.ACTION_MAIN
                }
                runOnUiThread {
                    statusText.text = getString(R.string.rx_tunnel_ready, profile.mName)
                    startActivity(start)
                }
            } catch (e: Exception) {
                runOnUiThread {
                    statusText.text = getString(R.string.rx_connect_failed, e.message ?: "unknown")
                }
            }
        }
    }

    private data class ParsedProfile(
        val remoteHost: String,
        val remotePort: Int,
        val caPem: String,
        val localPort: Int
    )

    private fun parseProfileForTunnel(profile: String): ParsedProfile {
        val remoteLine = profile.lineSequence().firstOrNull { it.trim().startsWith("remote ") }
            ?: error(getString(R.string.rx_err_no_remote))
        val remoteParts = remoteLine.trim().split(Regex("\\s+"))
        if (remoteParts.size < 3) error(getString(R.string.rx_err_remote_format))
        val host = remoteParts[1]
        val port = remoteParts[2].toIntOrNull() ?: error(getString(R.string.rx_err_remote_port))

        val caMatch = Pattern.compile("(?s)<ca>\\s*(.*?)\\s*</ca>").matcher(profile)
        if (!caMatch.find()) error(getString(R.string.rx_err_no_ca))
        val ca = caMatch.group(1)
        return ParsedProfile(
            remoteHost = host,
            remotePort = port,
            caPem = ca,
            localPort = 11941
        )
    }

    private fun rewriteProfileRemote(profile: String, localPort: Int): String {
        var replaced = false
        val out = profile.lineSequence()
            .mapNotNull { line ->
                val trimmed = line.trim()
                if (trimmed.startsWith("remote ")) {
                    if (!replaced) {
                        replaced = true
                        "remote 127.0.0.1 $localPort"
                    } else {
                        null
                    }
                } else {
                    line
                }
            }
            .toMutableList()
        if (!replaced) error(getString(R.string.rx_err_rewrite_remote))
        return out.joinToString("\n")
    }
}
