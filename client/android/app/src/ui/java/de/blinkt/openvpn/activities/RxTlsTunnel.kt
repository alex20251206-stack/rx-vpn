package de.blinkt.openvpn.activities

import java.io.ByteArrayInputStream
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.security.KeyStore
import java.security.cert.CertificateFactory
import java.security.cert.X509Certificate
import java.util.concurrent.Executors
import javax.net.ssl.SSLContext
import javax.net.ssl.TrustManagerFactory
import kotlin.concurrent.thread

object RxTlsTunnel {
    private var server: ServerSocket? = null
    private var running = false
    private val pool = Executors.newCachedThreadPool()

    @Synchronized
    fun restart(remoteHost: String, remotePort: Int, caPem: String, localPort: Int) {
        stop()
        val sslContext = sslContextFromCa(caPem)
        val socketFactory = sslContext.socketFactory
        val ss = ServerSocket()
        ss.reuseAddress = true
        ss.bind(InetSocketAddress(InetAddress.getByName("127.0.0.1"), localPort))
        server = ss
        running = true

        thread(name = "rx-tls-tunnel-accept", isDaemon = true) {
            while (running) {
                val plainClient = try {
                    ss.accept()
                } catch (_: Exception) {
                    break
                }
                pool.execute {
                    var upstream: Socket? = null
                    try {
                        upstream = socketFactory.createSocket(remoteHost, remotePort)
                        pumpBidirectional(plainClient, upstream)
                    } catch (_: Exception) {
                        try {
                            plainClient.close()
                        } catch (_: Exception) {
                        }
                        try {
                            upstream?.close()
                        } catch (_: Exception) {
                        }
                    }
                }
            }
        }
    }

    @Synchronized
    fun stop() {
        running = false
        try {
            server?.close()
        } catch (_: Exception) {
        }
        server = null
    }

    private fun pumpBidirectional(a: Socket, b: Socket) {
        val t1 = thread(isDaemon = true) {
            a.getInputStream().copyTo(b.getOutputStream())
            try {
                b.shutdownOutput()
            } catch (_: Exception) {
            }
        }
        val t2 = thread(isDaemon = true) {
            b.getInputStream().copyTo(a.getOutputStream())
            try {
                a.shutdownOutput()
            } catch (_: Exception) {
            }
        }
        t1.join()
        t2.join()
        try {
            a.close()
        } catch (_: Exception) {
        }
        try {
            b.close()
        } catch (_: Exception) {
        }
    }

    private fun sslContextFromCa(caPem: String): SSLContext {
        val cf = CertificateFactory.getInstance("X.509")
        val cert = cf.generateCertificate(ByteArrayInputStream(caPem.toByteArray())) as X509Certificate
        val ks = KeyStore.getInstance(KeyStore.getDefaultType())
        ks.load(null, null)
        ks.setCertificateEntry("rx-ca", cert)
        val tmf = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm())
        tmf.init(ks)
        return SSLContext.getInstance("TLS").apply { init(null, tmf.trustManagers, null) }
    }
}
