/* eslint-disable no-undef */

importScripts("https://www.gstatic.com/firebasejs/10.12.4/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/10.12.4/firebase-messaging-compat.js");

firebase.initializeApp({
    apiKey: "AIzaSyDTS4pouaoBIH2QF-iq-Flce9qWayDZGxc",
    authDomain: "mw-chat-prod.firebaseapp.com",
    projectId: "mw-chat-prod",
    storageBucket: "mw-chat-prod.firebasestorage.app",
    messagingSenderId: "1007212667628",
    appId: "1:1007212667628:web:ada75a68a6f79d9e2b7bc9",
    measurementId: "G-PRGEPSB3D2",
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
    console.log("[firebase-messaging-sw.js] Background message:", payload);
});
