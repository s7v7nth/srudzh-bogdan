package com.timofei.srudzhbogdan.ui

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.DirectionsRun
import androidx.compose.material.icons.automirrored.filled.MenuBook
import androidx.compose.material.icons.filled.AccountBalance
import androidx.compose.material.icons.filled.AddCircle
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.Build
import androidx.compose.material.icons.filled.Business
import androidx.compose.material.icons.filled.CardGiftcard
import androidx.compose.material.icons.filled.Checkroom
import androidx.compose.material.icons.filled.ChildCare
import androidx.compose.material.icons.filled.Cloud
import androidx.compose.material.icons.filled.ContentCut
import androidx.compose.material.icons.filled.CreditCard
import androidx.compose.material.icons.filled.CreditScore
import androidx.compose.material.icons.filled.DirectionsBus
import androidx.compose.material.icons.filled.DirectionsCar
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.Flight
import androidx.compose.material.icons.filled.GridView
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Laptop
import androidx.compose.material.icons.filled.LocalCafe
import androidx.compose.material.icons.filled.LocalGasStation
import androidx.compose.material.icons.filled.LocalOffer
import androidx.compose.material.icons.filled.MedicalServices
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.filled.Movie
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.Newspaper
import androidx.compose.material.icons.filled.Payments
import androidx.compose.material.icons.filled.People
import androidx.compose.material.icons.filled.Percent
import androidx.compose.material.icons.filled.Pets
import androidx.compose.material.icons.filled.Phone
import androidx.compose.material.icons.filled.QuestionMark
import androidx.compose.material.icons.filled.Restaurant
import androidx.compose.material.icons.filled.School
import androidx.compose.material.icons.filled.Security
import androidx.compose.material.icons.filled.ShoppingBag
import androidx.compose.material.icons.filled.ShoppingCart
import androidx.compose.material.icons.filled.SportsEsports
import androidx.compose.material.icons.filled.Storefront
import androidx.compose.material.icons.filled.Subscriptions
import androidx.compose.material.icons.filled.Umbrella
import androidx.compose.material.icons.filled.WaterDrop
import androidx.compose.material.icons.filled.Wifi
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import com.timofei.srudzh.core.AccountKind

/**
 * В данных значки хранятся именами из iPhone-версии (SF Symbols), чтобы копия переносилась между телефонами.
 * Здесь каждому имени подобран похожий значок Android.
 */
object AppIcons {
    private val map: Map<String, ImageVector> = mapOf(
        "cart" to Icons.Filled.ShoppingCart,
        "bus" to Icons.Filled.DirectionsBus,
        "house" to Icons.Filled.Home,
        "cup.and.saucer" to Icons.Filled.LocalCafe,
        "gamecontroller" to Icons.Filled.SportsEsports,
        "cross.case" to Icons.Filled.MedicalServices,
        "tshirt" to Icons.Filled.Checkroom,
        "percent" to Icons.Filled.Percent,
        "ellipsis.circle" to Icons.Filled.MoreHoriz,
        "banknote" to Icons.Filled.Payments,
        "gift" to Icons.Filled.CardGiftcard,
        "plus.circle" to Icons.Filled.AddCircle,
        "fork.knife" to Icons.Filled.Restaurant,
        "car" to Icons.Filled.DirectionsCar,
        "fuelpump" to Icons.Filled.LocalGasStation,
        "airplane" to Icons.Filled.Flight,
        "bag" to Icons.Filled.ShoppingBag,
        "book" to Icons.AutoMirrored.Filled.MenuBook,
        "graduationcap" to Icons.Filled.School,
        "pawprint" to Icons.Filled.Pets,
        "wifi" to Icons.Filled.Wifi,
        "phone" to Icons.Filled.Phone,
        "bolt" to Icons.Filled.Bolt,
        "drop" to Icons.Filled.WaterDrop,
        "film" to Icons.Filled.Movie,
        "music.note" to Icons.Filled.MusicNote,
        "figure.run" to Icons.AutoMirrored.Filled.DirectionsRun,
        "heart" to Icons.Filled.Favorite,
        "wrench.and.screwdriver" to Icons.Filled.Build,
        "tag" to Icons.Filled.LocalOffer,
        // Значки из набора категорий первой настройки iPhone-версии.
        "building.2" to Icons.Filled.Business,
        "icloud" to Icons.Filled.Cloud,
        "laptopcomputer" to Icons.Filled.Laptop,
        "lock.shield" to Icons.Filled.Security,
        "newspaper" to Icons.Filled.Newspaper,
        "play.rectangle" to Icons.Filled.Subscriptions,
        "scissors" to Icons.Filled.ContentCut,
        "sparkles" to Icons.Filled.AutoAwesome,
        "square.grid.2x2" to Icons.Filled.GridView,
        "storefront" to Icons.Filled.Storefront,
        "teddybear" to Icons.Filled.ChildCare,
        "umbrella" to Icons.Filled.Umbrella,
        "creditcard" to Icons.Filled.CreditCard,
        // Типы счетов.
        "building.columns" to Icons.Filled.AccountBalance,
        "creditcard.and.123" to Icons.Filled.CreditScore,
        "person.2" to Icons.Filled.People,
    )

    /** Значки, которые можно выбрать для категории (как в iPhone-версии). */
    val categoryChoices = listOf(
        "cart", "bus", "house", "cup.and.saucer", "gamecontroller", "cross.case", "tshirt", "percent",
        "ellipsis.circle", "banknote", "gift", "plus.circle", "fork.knife", "car", "fuelpump", "airplane",
        "bag", "book", "graduationcap", "pawprint", "wifi", "phone", "bolt", "drop", "film", "music.note",
        "figure.run", "heart", "wrench.and.screwdriver", "tag",
    )

    fun of(name: String?): ImageVector = map[name] ?: if (name == null) Icons.Filled.QuestionMark else Icons.Filled.LocalOffer

    fun account(kind: AccountKind): ImageVector = of(
        when (kind) {
            AccountKind.CARD -> "creditcard"
            AccountKind.CASH -> "banknote"
            AccountKind.SAVINGS -> "building.columns"
            AccountKind.CREDIT_LINE -> "creditcard.and.123"
            AccountKind.DEBT -> "person.2"
            AccountKind.LOAN -> "percent"
        },
    )
}

/** Цвета категорий: системные цвета iPhone в тёмной теме. */
object CategoryColors {
    val names = listOf("red", "orange", "yellow", "green", "mint", "teal", "blue", "indigo", "purple", "pink", "brown", "gray")

    fun of(name: String?): Color = when (name) {
        "red" -> Color(0xFFFF453A)
        "orange" -> Color(0xFFFF9F0A)
        "yellow" -> Color(0xFFFFD60A)
        "green" -> Color(0xFF30D158)
        "mint" -> Color(0xFF63E6E2)
        "teal" -> Color(0xFF40C8E0)
        "blue" -> Color(0xFF0A84FF)
        "indigo" -> Color(0xFF5E5CE6)
        "purple" -> Color(0xFFBF5AF2)
        "pink" -> Color(0xFFFF375F)
        "brown" -> Color(0xFFAC8E68)
        else -> Color(0xFF8E8E93)
    }
}
