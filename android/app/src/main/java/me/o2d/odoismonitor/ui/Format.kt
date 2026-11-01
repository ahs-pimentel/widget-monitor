package me.o2d.odoismonitor.ui

import java.text.NumberFormat
import java.time.Duration
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/** Formatação em pt-BR, igual à do Mac. */
object Fmt {
    private val br = Locale.forLanguageTag("pt-BR")

    private fun compact(v: Double): String = NumberFormat.getNumberInstance(br).apply {
        maximumFractionDigits = if (v < 10) 1 else 0
    }.format(v)

    /** 1234 → "1,2 mil"; 4_500_000 → "4,5 M"; 2_100_000_000 → "2,1 bi". */
    fun tokens(n: Long): String = when {
        n >= 1_000_000_000 -> compact(n / 1e9) + " bi"
        n >= 1_000_000 -> compact(n / 1e6) + " M"
        n >= 1_000 -> compact(n / 1e3) + " mil"
        else -> n.toString()
    }

    fun usd(v: Double): String = "US$ " + NumberFormat.getNumberInstance(br).apply {
        minimumFractionDigits = 2; maximumFractionDigits = if (v > 0 && v < 0.01) 4 else 2
    }.format(v)

    fun number(v: Double, digits: Int = 2): String = NumberFormat.getNumberInstance(br).apply {
        minimumFractionDigits = if (v % 1.0 == 0.0) 0 else digits; maximumFractionDigits = digits
    }.format(v)

    fun percent(fraction: Float): String = "${(fraction * 100).toInt()}%"

    fun bytes(b: Long): String {
        val gb = b / 1_073_741_824.0
        return if (gb >= 1) compact(gb) + " GB" else compact(b / 1_048_576.0) + " MB"
    }

    fun relative(at: Instant?, now: Instant = Instant.now()): String {
        if (at == null) return "—"
        val s = Duration.between(at, now).seconds
        return when {
            s < 60 -> "agora"
            s < 3600 -> "há ${s / 60} min"
            s < 86_400 -> "há ${s / 3600} h"
            else -> "há ${s / 86_400} d"
        }
    }

    fun until(at: Instant?, now: Instant = Instant.now()): String {
        if (at == null) return "—"
        val s = Duration.between(now, at).seconds.coerceAtLeast(0)
        val d = s / 86_400; val h = (s % 86_400) / 3600; val m = (s % 3600) / 60
        return when {
            d > 0 -> "em $d d $h h"
            h > 0 -> "em $h h $m min"
            else -> "em $m min"
        }
    }

    fun time(at: Instant?): String {
        if (at == null) return "—"
        val zoned = at.atZone(ZoneId.systemDefault())
        val today = zoned.toLocalDate() == Instant.now().atZone(ZoneId.systemDefault()).toLocalDate()
        return DateTimeFormatter.ofPattern(if (today) "HH:mm" else "EEE HH:mm", br).format(zoned)
    }

    /** 3725 s → "1:02:05"; abaixo de 1 h → "2:05". */
    fun clock(seconds: Double): String {
        val s = seconds.toLong().coerceAtLeast(0)
        val h = s / 3600; val m = (s % 3600) / 60; val sec = s % 60
        return if (h > 0) "%d:%02d:%02d".format(h, m, sec) else "%d:%02d".format(m, sec)
    }

    /** Iniciais dos dias dos últimos 7 dias, terminando hoje. */
    fun weekdays(): List<String> {
        val today = Instant.now().atZone(ZoneId.systemDefault()).toLocalDate()
        return (6 downTo 0).map {
            today.minusDays(it.toLong()).dayOfWeek.getDisplayName(java.time.format.TextStyle.NARROW, br).uppercase(br)
        }
    }

    fun activity(last: Instant?): String {
        if (last == null) return "Sem uso nos últimos 7 dias"
        val s = Duration.between(last, Instant.now()).seconds
        return when {
            s < 120 -> "Em uso agora"
            s < 600 -> "Ativo ${relative(last)}"
            else -> "Último uso ${relative(last)}"
        }
    }
}
