package k8sutils

import (
	"fmt"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

func Namespaced(object metav1.Object) string {
	return fmt.Sprintf("%s/%s", object.GetNamespace(), object.GetName())
}
