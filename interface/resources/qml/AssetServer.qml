//
//  AssetServer.qml
//
//  Created by Clement on  3/1/16
//  Copyright 2016 High Fidelity, Inc.
//
//  Distributed under the Apache License, Version 2.0.
//  See the accompanying file LICENSE or http://www.apache.org/licenses/LICENSE-2.0.html
//

import QtQuick 2.5
import QtQuick.Controls 1.4
import QtQuick.Dialogs 1.2 as OriginalDialogs
import Qt.labs.settings 1.0

import "styles-uit"
import "controls-uit" as HifiControls
import "windows-uit"
import "dialogs"

Window {
    id: root
    objectName: "AssetServer"
    title: "Asset Browser"
    resizable: true
    destroyOnInvisible: true
    x: 40; y: 40
    implicitWidth: 384; implicitHeight: 640
    minSize: Qt.vector2d(200, 300)

    property int colorScheme: hifi.colorSchemes.dark

    HifiConstants { id: hifi }

    property var scripts: ScriptDiscoveryService;
    property var assetProxyModel: Assets.proxyModel;
    property var assetMappingsModel: Assets.mappingModel;
    property var currentDirectory;

    Settings {
        category: "Overlay.AssetServer"
        property alias x: root.x
        property alias y: root.y
        property alias directory: root.currentDirectory
    }

    Component.onCompleted: {
        ApplicationInterface.uploadRequest.connect(uploadClicked);
        assetMappingsModel.errorGettingMappings.connect(handleGetMappingsError);
        reload();
    }

    function doDeleteFile(path) {
        console.log("Deleting " + path);

        Assets.deleteMappings(path, function(err) {
            if (err) {
                console.log("Asset browser - error deleting path: ", path, err);

                box = errorMessageBox("There was an error deleting:\n" + path + "\n" + err);
                box.selected.connect(reload);
            } else {
                console.log("Asset browser - finished deleting path: ", path);
                reload();
            }
        });

    }

    function doRenameFile(oldPath, newPath) {

        if (newPath[0] != "/") {
            newPath = "/" + newPath;
        }

        if (oldPath[oldPath.length - 1] == '/' && newPath[newPath.length - 1] != '/') {
            // this is a folder rename but the user neglected to add a trailing slash when providing a new path
            newPath = newPath + "/";
        }

        if (Assets.isKnownFolder(newPath)) {
            box = errorMessageBox("Cannot overwrite existing directory.");
            box.selected.connect(reload);
        }

        console.log("Asset browser - renaming " + oldPath + " to " + newPath);

        Assets.renameMapping(oldPath, newPath, function(err) {
            if (err) {
                console.log("Asset browser - error renaming: ", oldPath, "=>", newPath, " - error ", err);
                box = errorMessageBox("There was an error renaming:\n" + oldPath + " to " + newPath + "\n" + err);
                box.selected.connect(reload);
            } else {
                console.log("Asset browser - finished rename: ", oldPath, "=>", newPath);
            }

            reload();
        });
    }

    function fileExists(path) {
        return Assets.isKnownMapping(path);
    }

    function askForOverwrite(path, callback) {
        var object = desktop.messageBox({
            icon: hifi.icons.question,
            buttons: OriginalDialogs.StandardButton.Yes | OriginalDialogs.StandardButton.No,
            defaultButton: OriginalDialogs.StandardButton.No,
            title: "Overwrite File",
            text: path + "\n" + "This file already exists. Do you want to overwrite it?"
        });
        object.selected.connect(function(button) {
            if (button === OriginalDialogs.StandardButton.Yes) {
                callback();
            }
        });
    }

    function canAddToWorld(path) {
        var supportedExtensions = [/\.fbx\b/i, /\.obj\b/i];

        return supportedExtensions.reduce(function(total, current) {
            return total | new RegExp(current).test(path);
        }, false);
    }

    function clear() {
        Assets.mappingModel.clear();
    }

    function reload() {
        Assets.mappingModel.refresh();
        treeView.selection.clear();
    }

    function handleGetMappingsError(errorString) {
        errorMessageBox(
            "There was a problem retreiving the list of assets from your Asset Server.\n"
            + errorString
        );
    }

    function addToWorld() {
        var url = assetProxyModel.data(treeView.selection.currentIndex, 0x103);

        if (!url || !canAddToWorld(url)) {
            return;
        }

        var name = assetProxyModel.data(treeView.selection.currentIndex);

        console.log("Asset browser - adding asset " + url + " (" + name + ") to world.");

        var addPosition = Vec3.sum(MyAvatar.position, Vec3.multiply(2, Quat.getFront(MyAvatar.orientation)));
        Entities.addModelEntity(name, url, addPosition);
    }

    function copyURLToClipboard(index) {
        if (!index) {
            index = treeView.selection.currentIndex;
        }

        var url = assetProxyModel.data(treeView.selection.currentIndex, 0x103);
        if (!url) {
            return;
        }
        Window.copyToClipboard(url);
    }

    function renameEl(index, data) {
        if (!index) {
            return false;
        }

        var path = assetProxyModel.data(index, 0x100);
        if (!path) {
            return false;
        }

        var destinationPath = path.split('/');
        destinationPath[destinationPath.length - (path[path.length - 1] === '/' ? 2 : 1)] = data;
        destinationPath = destinationPath.join('/').trim();

        if (path === destinationPath) {
            return;
        }
        if (!fileExists(destinationPath)) {
            doRenameFile(path, destinationPath);
        }
    }
    function renameFile(index) {
        if (!index) {
            index = treeView.selection.currentIndex;
        }

        var path = assetProxyModel.data(index, 0x100);
        if (!path) {
            return;
        }

        var object = desktop.inputDialog({
            label: "Enter new path:",
            current: path,
            placeholderText: "Enter path here"
        });
        object.selected.connect(function(destinationPath) {
            destinationPath = destinationPath.trim();

            if (path == destinationPath) {
                return;
            }
            if (fileExists(destinationPath)) {
                askForOverwrite(destinationPath, function() {
                    doRenameFile(path, destinationPath);
                });
            } else {
                doRenameFile(path, destinationPath);
            }
        });
    }
    function deleteFile(index) {
        if (!index) {
            index = treeView.selection.currentIndex;
        }
        var path = assetProxyModel.data(index, 0x100);
        if (!path) {
            return;
        }

        var isFolder = assetProxyModel.data(treeView.selection.currentIndex, 0x101);
        var typeString = isFolder ? 'folder' : 'file';

        var object = desktop.messageBox({
            icon: hifi.icons.question,
            buttons: OriginalDialogs.StandardButton.Yes + OriginalDialogs.StandardButton.No,
            defaultButton: OriginalDialogs.StandardButton.Yes,
            title: "Delete",
            text: "You are about to delete the following " + typeString + ":\n" + path + "\nDo you want to continue?"
        });
        object.selected.connect(function(button) {
            if (button === OriginalDialogs.StandardButton.Yes) {
                doDeleteFile(path);
            }
        });
    }


    property var uploadOpen: false;
    Timer {
        id: timer
    }
    function uploadClicked(fileUrl) {
        if (uploadOpen) {
            return;
        }
        uploadOpen = true;

        function doUpload(url, dropping) {
            var fileUrl = fileDialogHelper.urlToPath(url);

            var path = assetProxyModel.data(treeView.selection.currentIndex, 0x100);
            var directory = path ? path.slice(0, path.lastIndexOf('/') + 1) : "/";
            var filename = fileUrl.slice(fileUrl.lastIndexOf('/') + 1);

            Assets.uploadFile(fileUrl, directory + filename,
                function() {
                    // Upload started
                    uploadSpinner.visible = true;
                    uploadButton.enabled = false;
                    uploadProgressLabel.text = "In progress...";
                },
                function(err, path) {
                    print(err, path);
                    if (!err) {
                        uploadProgressLabel.text = "Upload Complete";
                        timer.interval = 1000;
                        timer.repeat = false;
                        timer.triggered.connect(function() {
                            uploadSpinner.visible = false;
                            uploadButton.enabled = true;
                            uploadOpen = false;
                        });
                        timer.start();
                        console.log("Asset Browser - finished uploading: ", fileUrl);
                        reload();
                    } else {
                        if (err > 0) {
                            console.log("Asset Browser - error uploading: ", fileUrl, " - error ", err);
                            var box = errorMessageBox("There was an error uploading:\n" + fileUrl + "\n" + Assets.getErrorString(err));
                            box.selected.connect(reload);
                        }
                        uploadSpinner.visible = false;
                        uploadButton.enabled = true;
                        uploadOpen = false;
                    }
            }, dropping);
        }

        if (fileUrl) {
            doUpload(fileUrl, true);
        } else {
            var browser = desktop.fileDialog({
                selectDirectory: false,
                dir: currentDirectory
            });
            browser.canceled.connect(function() {
                uploadOpen = false;
            });
            browser.selectedFile.connect(function(url) {
                currentDirectory = browser.dir;
                doUpload(url, false);
            });
        }
    }

    function errorMessageBox(message) {
        return desktop.messageBox({
            icon: hifi.icons.warning,
            defaultButton: OriginalDialogs.StandardButton.Ok,
            title: "Error",
            text: message
        });
    }

    Item {
        width: pane.contentWidth
        height: pane.height

        HifiControls.ContentSection {
            id: assetDirectory
            name: "Asset Directory"
            spacing: hifi.dimensions.contentSpacing.y
            isFirst: true

            Row {
                id: buttonRow
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: hifi.dimensions.contentSpacing.x

                HifiControls.GlyphButton {
                    glyph: hifi.glyphs.reload
                    color: hifi.buttons.white
                    colorScheme: root.colorScheme
                    height: 26
                    width: 26

                    onClicked: root.reload()
                }

                HifiControls.Button {
                    text: "ADD TO WORLD"
                    color: hifi.buttons.white
                    colorScheme: root.colorScheme
                    height: 26
                    width: 120

                    enabled: canAddToWorld(assetProxyModel.data(treeView.selection.currentIndex, 0x100))

                    onClicked: root.addToWorld()
                }

                HifiControls.Button {
                    text: "RENAME"
                    color: hifi.buttons.white
                    colorScheme: root.colorScheme
                    height: 26
                    width: 80

                    onClicked: root.renameFile()
                    enabled: treeView.selection.hasSelection
                }

                HifiControls.Button {
                    id: deleteButton

                    text: "DELETE"
                    color: hifi.buttons.red
                    colorScheme: root.colorScheme
                    height: 26
                    width: 80

                    onClicked: root.deleteFile()
                    enabled: treeView.selection.hasSelection
                }
            }

            Menu {
                id: contextMenu
                title: "Edit"
                property var url: ""
                property var currentIndex: null

                MenuItem {
                    text: "Copy URL"
                    onTriggered: {
                        copyURLToClipboard(contextMenu.currentIndex);
                    }
                }

                MenuItem {
                    text: "Rename"
                    onTriggered: {
                        renameFile(contextMenu.currentIndex);
                    }
                }

                MenuItem {
                    text: "Delete"
                    onTriggered: {
                        deleteFile(contextMenu.currentIndex);
                    }
                }
            }
        }

        HifiControls.Tree {
            id: treeView
            anchors.top: assetDirectory.bottom
            anchors.bottom: uploadSection.top
            anchors.margins: 12
            anchors.left: parent.left
            anchors.right: parent.right

            treeModel: assetProxyModel
            canEdit: true
            colorScheme: root.colorScheme

            modifyEl: renameEl

            MouseArea {
                propagateComposedEvents: true
                anchors.fill: parent
                acceptedButtons: Qt.RightButton
                onClicked: {
                    var index = treeView.indexAt(mouse.x, mouse.y);

                    treeView.selection.setCurrentIndex(index, 0x0002);

                    contextMenu.currentIndex = index;
                    contextMenu.popup();
                }
            }
        }
        HifiControls.ContentSection {
            id: uploadSection
            name: "Upload A File"
            spacing: hifi.dimensions.contentSpacing.y
            anchors.bottom: parent.bottom
            height: 92

            Item {
                height: parent.height
                width: parent.width
                HifiControls.Button {
                    id: uploadButton
                    anchors.right: parent.right

                    text: "Choose File"
                    color: hifi.buttons.blue
                    colorScheme: root.colorScheme
                    height: 30
                    width: 155

                    onClicked: uploadClickedTimer.running = true

                    // For some reason trigginer an API that enters
                    // an internal event loop directly from the button clicked
                    // trigger below causes the appliction to behave oddly.
                    // Most likely because the button onClicked handling is never
                    // completed until the function returns.
                    // FIXME find a better way of handling the input dialogs that
                    // doesn't trigger this.
                    Timer {
                        id: uploadClickedTimer
                        interval: 5
                        repeat: false
                        running: false
                        onTriggered: uploadClicked();
                    }
                }

                Item {
                    id: uploadSpinner
                    visible: false
                    anchors.top: parent.top
                    anchors.left: parent.left
                    width: 40
                    height: 32

                    Image {
                        id: image
                        width: 24
                        height: 24
                        source: "../images/Loading-Outer-Ring.png"
                        RotationAnimation on rotation {
                            loops: Animation.Infinite
                            from: 0
                            to: 360
                            duration: 2000
                        }
                    }
                    Image {
                        width: 24
                        height: 24
                        source: "../images/Loading-Inner-H.png"
                    }
                    HifiControls.Label {
                        id: uploadProgressLabel
                        anchors.left: image.right
                        anchors.leftMargin: 10
                        anchors.verticalCenter: image.verticalCenter
                        text: "In progress..."
                        colorScheme: root.colorScheme
                    }

                }
            }

        }
    }
}
